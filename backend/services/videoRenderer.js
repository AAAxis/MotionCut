/**
 * Video Renderer — composites stock footage + text overlays + transitions via ffmpeg
 */
const ffmpeg = require('fluent-ffmpeg');
const fs = require('fs');
const path = require('path');
const { v4: uuid } = require('uuid');
const { downloadVideo } = require('./stockFootage');
const { generateSceneVoiceovers } = require('./voiceover');

const OUTPUT_DIR = path.join(__dirname, '..', 'output');
const TEMP_DIR = path.join(__dirname, '..', 'temp');

if (process.env.FFMPEG_PATH) ffmpeg.setFfmpegPath(process.env.FFMPEG_PATH);

function ensureDir(dir) {
  if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
}

/**
 * Render a single scene: trim stock footage to scene duration, add text overlay (video only)
 */
function renderScene(inputPath, outputPath, scene) {
  return new Promise((resolve, reject) => {
    const text = (scene.textOverlay || '').replace(/'/g, "'\\''").replace(/:/g, '\\:');
    const duration = scene.duration || 5;

    const drawtext = [
      `drawtext=text='${text}'`,
      `fontsize=56`,
      `fontcolor=white`,
      `fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf`,
      `x=(w-text_w)/2`,
      `y=(h-text_h)/2`,
      `box=1`,
      `boxcolor=black@0.5`,
      `boxborderw=20`,
      `enable='between(t,0.5,${duration - 0.5})'`,
    ].join(':');

    ffmpeg(inputPath)
      .duration(duration)
      .videoFilters([
        'scale=1920:1080:force_original_aspect_ratio=decrease',
        'pad=1920:1080:(ow-iw)/2:(oh-ih)/2:black',
        drawtext,
      ])
      .outputOptions([
        '-c:v libx264', '-preset fast', '-crf 23',
        '-r 30', '-pix_fmt yuv420p', '-an',
      ])
      .output(outputPath)
      .on('end', resolve)
      .on('error', reject)
      .run();
  });
}

/**
 * Concatenate voiceover audio files into one continuous track
 */
function concatenateAudio(audioPaths, scenes, outputPath) {
  return new Promise((resolve, reject) => {
    const listFile = outputPath + '.txt';
    const lines = [];

    for (let i = 0; i < scenes.length; i++) {
      const duration = scenes[i].duration || 5;
      if (audioPaths[i] && fs.existsSync(audioPaths[i])) {
        lines.push(`file '${audioPaths[i]}'`);
      } else {
        // Generate silence for scenes without voiceover
        const silencePath = path.join(path.dirname(outputPath), `silence_${i}.mp3`);
        // We'll generate silence inline via ffmpeg later
        lines.push(`file '${audioPaths[i] || ''}'`);
      }
    }

    // Simpler: use ffmpeg to concat audio with padding
    // Build a complex filter that pads/trims each audio to scene duration
    const cmd = ffmpeg();
    const filters = [];
    const inputs = [];

    for (let i = 0; i < scenes.length; i++) {
      const duration = scenes[i].duration || 5;
      if (audioPaths[i] && fs.existsSync(audioPaths[i])) {
        cmd.input(audioPaths[i]);
        // Pad audio to scene duration (in case voiceover is shorter)
        filters.push(`[${inputs.length}]apad=whole_dur=${duration},atrim=0:${duration},asetpts=PTS-STARTPTS[a${i}]`);
      } else {
        cmd.input(`anullsrc=r=44100:cl=stereo`);
        cmd.inputOptions(['-f lavfi', '-t', String(duration)]);
        filters.push(`[${inputs.length}]asetpts=PTS-STARTPTS[a${i}]`);
      }
      inputs.push(i);
    }

    const concatInputs = inputs.map((_, i) => `[a${i}]`).join('');
    filters.push(`${concatInputs}concat=n=${inputs.length}:v=0:a=1[out]`);

    cmd.complexFilter(filters, 'out')
      .outputOptions(['-c:a aac', '-b:a 128k'])
      .output(outputPath)
      .on('end', resolve)
      .on('error', reject)
      .run();
  });
}

/**
 * Merge video (no audio) with voiceover audio track
 */
function mergeVideoAudio(videoPath, audioPath, outputPath) {
  return new Promise((resolve, reject) => {
    ffmpeg(videoPath)
      .input(audioPath)
      .outputOptions([
        '-c:v copy',
        '-c:a aac',
        '-b:a 128k',
        '-shortest',
        '-movflags +faststart',
      ])
      .output(outputPath)
      .on('end', resolve)
      .on('error', reject)
      .run();
  });
}

/**
 * Concatenate rendered scenes into final video
 */
function concatenateScenes(scenePaths, outputPath) {
  return new Promise((resolve, reject) => {
    const listFile = path.join(TEMP_DIR, `concat_${uuid()}.txt`);
    const content = scenePaths.map(p => `file '${p}'`).join('\n');
    fs.writeFileSync(listFile, content);

    ffmpeg()
      .input(listFile)
      .inputOptions(['-f concat', '-safe 0'])
      .outputOptions([
        '-c:v libx264',
        '-preset fast',
        '-crf 22',
        '-r 30',
        '-pix_fmt yuv420p',
        '-movflags +faststart',
      ])
      .output(outputPath)
      .on('end', () => {
        fs.unlinkSync(listFile);
        resolve();
      })
      .on('error', reject)
      .run();
  });
}

/**
 * Full render pipeline: download footage → render scenes → concatenate
 */
async function renderVideo(scenesWithFootage, generationId, options = {}) {
  ensureDir(OUTPUT_DIR);
  ensureDir(TEMP_DIR);

  const jobDir = path.join(TEMP_DIR, generationId);
  ensureDir(jobDir);

  // 1. Generate voiceovers
  const hasVoiceover = process.env.ELEVENLABS_API_KEY && scenesWithFootage.some(s => s.voiceover);
  let voiceoverPaths = [];

  if (hasVoiceover) {
    console.log('Generating voiceovers...');
    voiceoverPaths = await generateSceneVoiceovers(scenesWithFootage, jobDir, {
      voiceId: options.voiceId,
    });
  }

  // 2. Download + render video scenes
  const renderedPaths = [];

  for (let i = 0; i < scenesWithFootage.length; i++) {
    const scene = scenesWithFootage[i];

    if (!scene.footage?.url) {
      console.warn(`Scene ${i + 1}: No footage, generating color card`);
      const cardPath = path.join(jobDir, `scene_${i}_card.mp4`);
      await renderColorCard(cardPath, scene);
      renderedPaths.push(cardPath);
      continue;
    }

    const rawPath = path.join(jobDir, `scene_${i}_raw.mp4`);
    console.log(`Scene ${i + 1}: Downloading ${scene.footage.url}`);
    await downloadVideo(scene.footage.url, rawPath);

    const renderedPath = path.join(jobDir, `scene_${i}_rendered.mp4`);
    console.log(`Scene ${i + 1}: Rendering with text overlay`);
    await renderScene(rawPath, renderedPath, scene);
    renderedPaths.push(renderedPath);
  }

  // 3. Concatenate video scenes (no audio)
  const silentVideoPath = path.join(jobDir, 'video_silent.mp4');
  console.log('Concatenating video scenes...');
  await concatenateScenes(renderedPaths, silentVideoPath);

  // 4. Merge voiceover if available
  const finalPath = path.join(OUTPUT_DIR, `${generationId}.mp4`);

  if (hasVoiceover && voiceoverPaths.some(p => p)) {
    console.log('Merging voiceover audio...');
    const fullAudioPath = path.join(jobDir, 'voiceover_full.aac');
    await concatenateAudio(voiceoverPaths, scenesWithFootage, fullAudioPath);
    await mergeVideoAudio(silentVideoPath, fullAudioPath, finalPath);
  } else {
    fs.copyFileSync(silentVideoPath, finalPath);
  }

  // 5. Cleanup temp
  try {
    fs.rmSync(jobDir, { recursive: true, force: true });
  } catch (e) { /* ignore */ }

  return {
    path: finalPath,
    filename: `${generationId}.mp4`,
    url: `/output/${generationId}.mp4`,
  };
}

/**
 * Generate a solid color card with text (fallback when no footage found)
 */
function renderColorCard(outputPath, scene) {
  return new Promise((resolve, reject) => {
    const text = (scene.textOverlay || 'No footage').replace(/'/g, "'\\''").replace(/:/g, '\\:');
    const duration = scene.duration || 5;

    ffmpeg()
      .input(`color=c=#1a1a2e:s=1920x1080:d=${duration}`)
      .inputOptions(['-f lavfi'])
      .videoFilters([
        `drawtext=text='${text}':fontsize=64:fontcolor=white:fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf:x=(w-text_w)/2:y=(h-text_h)/2`,
      ])
      .outputOptions([
        '-c:v libx264',
        '-preset fast',
        '-crf 23',
        '-r 30',
        '-pix_fmt yuv420p',
        '-t', String(duration),
      ])
      .output(outputPath)
      .on('end', resolve)
      .on('error', reject)
      .run();
  });
}

module.exports = { renderVideo, renderScene, concatenateScenes, mergeVideoAudio };
