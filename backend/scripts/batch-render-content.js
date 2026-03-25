#!/usr/bin/env node
/**
 * Batch Content Video Renderer
 *
 * Reads TikTok content scripts from tiktok-content/scripts/,
 * converts them into fal.ai video prompts, generates clips,
 * adds TTS voiceover, and merges into final videos.
 *
 * Usage:
 *   node batch-render-content.js                    # render all unrendered scripts
 *   node batch-render-content.js --week 1           # render week 1 only
 *   node batch-render-content.js --script W1-M1     # render specific script
 *   node batch-render-content.js --dry-run          # preview prompts without generating
 *   node batch-render-content.js --list             # list scripts and their render status
 */
require('dotenv').config({ path: require('path').join(__dirname, '..', '.env') });

const fs = require('fs');
const path = require('path');
const os = require('os');
const { execSync } = require('child_process');
const { v4: uuid } = require('uuid');
const { fal } = require('@fal-ai/client');

const FAL_KEY = process.env.FAL_KEY || '';
const OPENROUTER_KEY = process.env.OPENROUTER_API_KEY || '';  // optional — used for AI prompt enhancement
const REPLICATE_TOKEN = process.env.REPLICATE_API_TOKEN || '';
const FAL_VIDEO_MODEL = 'fal-ai/pixverse/v4/text-to-video';
const TTS_MODEL = 'minimax/speech-02-hd';

if (FAL_KEY) fal.config({ credentials: FAL_KEY });

const CONTENT_DIR = path.join(__dirname, '..', '..', 'tiktok-content', 'scripts');
const OUTPUT_DIR = path.join(__dirname, '..', 'output', 'content-videos');
const STATUS_FILE = path.join(OUTPUT_DIR, 'render-status.json');

const delay = ms => new Promise(r => setTimeout(r, ms));

// ===== Parse CLI args =====
const args = process.argv.slice(2);
const flags = {};
for (let i = 0; i < args.length; i++) {
  if (args[i] === '--week') flags.week = parseInt(args[++i]);
  else if (args[i] === '--script') flags.script = args[++i];
  else if (args[i] === '--dry-run') flags.dryRun = true;
  else if (args[i] === '--list') flags.list = true;
  else if (args[i] === '--force') flags.force = true;
}

// ===== Status tracking =====
function loadStatus() {
  if (fs.existsSync(STATUS_FILE)) return JSON.parse(fs.readFileSync(STATUS_FILE, 'utf8'));
  return {};
}

function saveStatus(status) {
  fs.mkdirSync(OUTPUT_DIR, { recursive: true });
  fs.writeFileSync(STATUS_FILE, JSON.stringify(status, null, 2));
}

// ===== Script parsing =====
function discoverScripts() {
  const scripts = [];
  if (!fs.existsSync(CONTENT_DIR)) {
    console.error(`Content directory not found: ${CONTENT_DIR}`);
    process.exit(1);
  }

  for (let week = 1; week <= 4; week++) {
    const weekDir = path.join(CONTENT_DIR, `week-${week}`);
    if (!fs.existsSync(weekDir)) continue;

    const files = fs.readdirSync(weekDir).filter(f => f.endsWith('.md')).sort();
    for (const file of files) {
      const id = file.replace('.md', '');
      scripts.push({ id, week, file, path: path.join(weekDir, file) });
    }
  }
  return scripts;
}

function parseScript(filepath) {
  const content = fs.readFileSync(filepath, 'utf8');
  const result = {
    title: '',
    pillar: '',
    format: '',
    length: '',
    energy: '',
    hook: { visual: '', text: '', audio: '' },
    body: [],
    cta: { visual: '', text: '', audio: '' },
    caption: '',
    hashtags: '',
    raw: content,
  };

  // Extract header
  const titleMatch = content.match(/^#\s+SCRIPT\s+[\w-]+:\s+"(.+)"/m);
  if (titleMatch) result.title = titleMatch[1];

  const pillarMatch = content.match(/\*\*Pillar:\*\*\s+(.+?)\s*\|/);
  if (pillarMatch) result.pillar = pillarMatch[1].trim();

  const formatMatch = content.match(/\*\*Format:\*\*\s+(.+)/m);
  if (formatMatch) result.format = formatMatch[1].trim();

  const lengthMatch = content.match(/\*\*Length:\*\*\s+(.+)/m);
  if (lengthMatch) result.length = lengthMatch[1].trim();

  const energyMatch = content.match(/\*\*Energy:\*\*\s+(.+)/m);
  if (energyMatch) result.energy = energyMatch[1].trim();

  // Extract HOOK section
  const hookSection = content.match(/## HOOK[\s\S]*?(?=## BODY|## CTA|---)/);
  if (hookSection) {
    const hVisual = hookSection[0].match(/\*\*VISUAL:\*\*\s*(.+)/);
    const hText = hookSection[0].match(/\*\*TEXT OVERLAY:\*\*\s*(.+)/);
    const hAudio = hookSection[0].match(/\*\*AUDIO:\*\*\s*(.+)/);
    if (hVisual) result.hook.visual = hVisual[1].trim();
    if (hText) result.hook.text = hText[1].replace(/"/g, '').trim();
    if (hAudio) result.hook.audio = hAudio[1].replace(/"/g, '').trim();
  }

  // Extract BODY shots
  const bodySection = content.match(/## BODY[\s\S]*?(?=## CTA|---)/);
  if (bodySection) {
    const shots = bodySection[0].split(/\*\*Shot \d+/).slice(1);
    for (const shot of shots) {
      const visual = shot.match(/VISUAL:\s*(.+)/);
      const text = shot.match(/TEXT OVERLAY:\s*(.+)/);
      const audio = shot.match(/AUDIO:\s*(.+)/);
      result.body.push({
        visual: visual ? visual[1].trim() : '',
        text: text ? text[1].replace(/"/g, '').trim() : '',
        audio: audio ? audio[1].replace(/"/g, '').trim() : '',
      });
    }
  }

  // Extract CTA section
  const ctaSection = content.match(/## CTA[\s\S]*?(?=---)/);
  if (ctaSection) {
    const cVisual = ctaSection[0].match(/\*\*VISUAL:\*\*\s*(.+)/);
    const cText = ctaSection[0].match(/\*\*TEXT OVERLAY:\*\*\s*(.+)/);
    const cAudio = ctaSection[0].match(/\*\*AUDIO:\*\*\s*(.+)/);
    if (cVisual) result.cta.visual = cVisual[1].trim();
    if (cText) result.cta.text = cText[1].replace(/"/g, '').trim();
    if (cAudio) result.cta.audio = cAudio[1].replace(/"/g, '').trim();
  }

  // Extract caption
  const captionMatch = content.match(/## CAPTION\s*```\s*([\s\S]*?)```/);
  if (captionMatch) result.caption = captionMatch[1].trim();

  return result;
}

// ===== Convert script scenes to fal.ai video prompts =====
// Two modes: if OPENROUTER_KEY is set, uses AI enhancement. Otherwise, builds prompts locally from script visuals.

const PILLAR_STYLES = {
  'Wow Factor': 'dramatic cinematic lighting, vibrant colors, eye-catching, epic feel',
  'Quick Tips': 'clean modern tech aesthetic, soft professional lighting, minimal',
  'Trend Rides': 'trendy energetic vibe, dynamic movement, bold colors',
  'Relatable/Funny': 'warm natural lighting, casual setting, expressive person',
  'Behind the Scenes': 'authentic casual workspace, warm ambient light, candid feel',
  'Direct Promo': 'polished professional, product showcase, sleek modern',
};

function cleanVisualForPrompt(visual) {
  // Strip app-specific / screen-recording references — fal.ai generates cinematic b-roll, not UI
  let cleaned = visual
    .replace(/screen\s*record(ing)?/gi, '')
    .replace(/\b(CreatorAI|Reel Creator|app icon|home screen|Control Center|Do Not Disturb)\b/gi, '')
    .replace(/\b(app|tab|button|phone screen|swipe|tap|menu|UI|interface|loading|processing|animation)\b/gi, '')
    .replace(/\b(PiP|face cam|front camera|screen|recording|preview)\b/gi, '')
    .replace(/\bShow(ing)?\b/gi, '')
    .replace(/\bLet it\b[^.]*\./gi, '')
    .replace(/\bso viewers\b[^.]*\./gi, '')
    .replace(/Close-up of\s*\.\s*/gi, '')
    .replace(/Back to\s+briefly\b/gi, '')
    .replace(/Cut to\s*/gi, '')
    .replace(/Finger types\b[^.]*\./gi, '')
    .replace(/\btap(ped|ping|s)?\b[^.,]*/gi, '')
    .replace(/\bTyp(e|ing|ed)\b[^.]*into[^.]*/gi, '')
    .replace(/Phone\s*—?\s*/gi, '')
    .replace(/on\s*'s\b/gi, '')
    .replace(/[—–]/g, ', ')
    .replace(/\.\.\s*/g, '. ')
    .replace(/\s*,\s*,+/g, ',')
    .replace(/^\s*[,.\s]+/, '')
    .replace(/[,.\s]+$/, '')
    .replace(/\s+/g, ' ')
    .trim();

  // If cleaning left too little, return empty so fallback kicks in
  if (cleaned.length < 15) return '';
  return cleaned;
}

function buildPromptFromTitle(parsed) {
  const style = PILLAR_STYLES[parsed.pillar] || PILLAR_STYLES['Wow Factor'];
  const title = parsed.title || 'creative content';

  // Map pillar to different visual scenarios
  const scenarios = {
    'Wow Factor': [
      `Close-up of a young creative person staring at a glowing phone screen in awe, neon purple and blue lighting reflecting on their face, dark room, vertical 9:16 cinematic shot`,
      `Dramatic slow-motion shot of digital particles forming into a video frame, ${style}, dark background with vibrant light trails, vertical 9:16`,
      `Confident young person holding up their phone showing a completed video, proud smile, ${style}, vertical 9:16 cinematic`,
    ],
    'Quick Tips': [
      `Clean overhead shot of a modern desk with a phone and laptop, hands interacting with the device, soft natural lighting, vertical 9:16 professional`,
      `Close-up of fingers smoothly swiping on a phone screen, clean minimal workspace background, soft warm lighting, vertical 9:16`,
      `Young professional nodding with a satisfied expression, modern office background, clean aesthetic, vertical 9:16`,
    ],
    'Relatable/Funny': [
      `Person sitting at a desk looking exhausted and frustrated at their laptop, dramatic comedic lighting, vertical 9:16 cinematic`,
      `Same person suddenly perking up with an excited expression, bright warm lighting shift, vertical 9:16`,
      `Person smiling smugly at camera with a wink, casual home setting, warm lighting, vertical 9:16`,
    ],
    'Trend Rides': [
      `Dynamic shot of a trendy young person dancing or moving energetically, colorful neon background, vertical 9:16 cinematic`,
      `Fast-paced montage-style shot of creative content being made, bold vibrant colors, dynamic movement, vertical 9:16`,
      `Person pointing at camera with confidence, trendy outfit, energetic pose, colorful background, vertical 9:16`,
    ],
    'Behind the Scenes': [
      `Candid shot of a person working on a laptop in a cozy workspace, warm ambient lighting, plants and coffee visible, vertical 9:16`,
      `Close-up of hands typing on a keyboard with code or designs visible on screen, warm desk lamp lighting, vertical 9:16`,
      `Person turning to camera from their workspace with a genuine smile, natural lighting, authentic feel, vertical 9:16`,
    ],
    'Direct Promo': [
      `Sleek product showcase shot of a phone with a glowing screen, dark premium background, professional lighting, vertical 9:16`,
      `Person confidently using their phone, impressed expression, clean modern background, vertical 9:16`,
      `Bold cinematic shot zooming into a phone screen, premium feel, dramatic lighting, vertical 9:16`,
    ],
  };

  return scenarios[parsed.pillar] || scenarios['Wow Factor'];
}

function buildLocalPrompts(parsed) {
  // Always use title-based cinematic prompts — much more reliable with fal.ai
  // The script visual descriptions are too app/UI-focused for AI video generation
  return buildPromptFromTitle(parsed);
}

async function scriptToVideoPromptsAI(parsed) {
  const scenes = [parsed.hook, ...parsed.body, parsed.cta]
    .filter(s => s.visual)
    .map(s => s.visual)
    .join('\n');

  const res = await fetch('https://openrouter.ai/api/v1/chat/completions', {
    method: 'POST',
    headers: { 'Authorization': `Bearer ${OPENROUTER_KEY}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({
      model: 'google/gemini-2.0-flash-001',
      messages: [{ role: 'user', content: `You are a video prompt engineer for AI video generation models (PixVerse, Sora, Kling).

Convert these TikTok content script scenes into 3 cinematic AI video generation prompts.

CONTENT TITLE: "${parsed.title}"
PILLAR: ${parsed.pillar}
ENERGY: ${parsed.energy}

SCENES FROM SCRIPT:
${scenes}

RULES:
- Output EXACTLY 3 prompts, numbered 1. 2. 3.
- Each prompt = 1-2 sentences, highly visual and descriptive
- Vertical 9:16 framing, cinematic lighting
- NO text, NO UI, NO app screenshots in the video — these are b-roll/background clips
- If the script is about the app, create MOOD/AESTHETIC clips that match the energy
- For "Wow Factor" pillar: dramatic, eye-catching, cinematic
- For "Quick Tips" pillar: clean, tech-aesthetic, professional
- For "Relatable/Funny" pillar: expressive person, comedic timing, relatable setting
- For "Behind the Scenes" pillar: casual, authentic, workspace vibes
- Each scene must be VISUALLY DIFFERENT (different setting, angle, mood)
- 5 seconds each clip` }],
      max_tokens: 400,
    }),
  });
  const data = await res.json();
  const text = data.choices?.[0]?.message?.content?.trim() || '';
  const prompts = text.split('\n').map(l => l.replace(/^\d+[\.\)]\s*/, '').trim()).filter(l => l.length > 10);
  while (prompts.length < 3) prompts.push('Cinematic vertical shot of a creative person working on content, moody neon lighting, 9:16 aspect ratio');
  return prompts.slice(0, 3);
}

async function scriptToVideoPrompts(parsed) {
  // Use AI enhancement if OpenRouter key is available, otherwise build locally
  if (OPENROUTER_KEY) {
    try {
      return await scriptToVideoPromptsAI(parsed);
    } catch (err) {
      console.log(`  OpenRouter failed (${err.message}), falling back to local prompt builder`);
    }
  }
  return buildLocalPrompts(parsed);
}

// ===== AI: Generate voiceover text from script =====
function extractVoiceover(parsed) {
  const parts = [];
  if (parsed.hook.audio) parts.push(parsed.hook.audio);
  for (const shot of parsed.body) {
    if (shot.audio && !shot.audio.startsWith('[')) parts.push(shot.audio);
  }
  if (parsed.cta.audio) parts.push(parsed.cta.audio);

  let voiceover = parts.join(' ').replace(/[—–]/g, ', ');
  // Clean up stage directions in brackets
  voiceover = voiceover.replace(/\[.*?\]/g, '').replace(/\s+/g, ' ').trim();
  return voiceover;
}

// ===== fal.ai video generation =====
async function generateClip(prompt, retries = 2) {
  for (let attempt = 0; attempt <= retries; attempt++) {
    try {
      const result = await fal.subscribe(FAL_VIDEO_MODEL, {
        input: { prompt, duration: '5', aspect_ratio: '9:16', quality: 'high' },
        logs: false,
        pollInterval: 5000,
      });
      if (result.data?.video?.url) return result.data.video.url;
      throw new Error('No video URL in response');
    } catch (err) {
      if (attempt < retries) {
        console.log(`  Retry ${attempt + 1}/${retries}: ${err.message}`);
        await delay(5000);
      } else throw err;
    }
  }
}

// ===== Replicate TTS =====
async function generateTTS(text) {
  const res = await fetch('https://api.replicate.com/v1/models/minimax/speech-02-hd/predictions', {
    method: 'POST',
    headers: { 'Authorization': `Bearer ${REPLICATE_TOKEN}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ input: { text, voice_id: 'English_CaptivatingStoryteller', speed: 1.1, emotion: 'happy' } }),
  });
  const pred = await res.json();
  if (!pred.id) throw new Error(`TTS creation failed: ${JSON.stringify(pred).substring(0, 200)}`);

  const start = Date.now();
  while (Date.now() - start < 60000) {
    const poll = await fetch(`https://api.replicate.com/v1/predictions/${pred.id}`, {
      headers: { 'Authorization': `Bearer ${REPLICATE_TOKEN}` },
    }).then(r => r.json());
    if (poll.status === 'succeeded') return poll.output;
    if (poll.status === 'failed') throw new Error(`TTS failed: ${poll.error}`);
    await delay(3000);
  }
  throw new Error('TTS timed out');
}

// ===== File helpers =====
async function downloadFile(url, filepath) {
  const res = await fetch(url);
  if (!res.ok) throw new Error(`Download failed: ${res.status}`);
  fs.writeFileSync(filepath, Buffer.from(await res.arrayBuffer()));
}

function mergeClipsWithAudio(videoPaths, audioPath, outputPath) {
  const concatFile = outputPath + '.concat.txt';
  fs.writeFileSync(concatFile, videoPaths.map(p => `file '${p}'`).join('\n'));

  if (audioPath && fs.existsSync(audioPath)) {
    const audioDur = execSync(`ffprobe -v error -show_entries format=duration -of csv=p=0 "${audioPath}"`).toString().trim();
    execSync(`ffmpeg -y -f concat -safe 0 -i "${concatFile}" -i "${audioPath}" -c:v libx264 -c:a aac -map 0:v:0 -map 1:a:0 -t ${audioDur} -shortest -pix_fmt yuv420p -movflags +faststart "${outputPath}" 2>/dev/null`);
  } else {
    execSync(`ffmpeg -y -f concat -safe 0 -i "${concatFile}" -c:v libx264 -pix_fmt yuv420p -movflags +faststart "${outputPath}" 2>/dev/null`);
  }
  try { fs.unlinkSync(concatFile); } catch(e) {}
}

// ===== Render a single script =====
async function renderScript(scriptInfo, status) {
  const { id, path: scriptPath } = scriptInfo;
  const jobId = `${id}-${uuid().substring(0, 8)}`;
  const tmpDir = path.join(os.tmpdir(), `content-${jobId}`);
  fs.mkdirSync(tmpDir, { recursive: true });

  console.log(`\n${'='.repeat(60)}`);
  console.log(`RENDERING: ${id}`);
  console.log(`${'='.repeat(60)}`);

  try {
    // 1. Parse script
    console.log(`[1/5] Parsing script...`);
    const parsed = parseScript(scriptPath);
    console.log(`  Title: "${parsed.title}"`);
    console.log(`  Pillar: ${parsed.pillar} | Format: ${parsed.format} | Length: ${parsed.length}`);

    // 2. Generate video prompts
    console.log(`[2/5] Generating video prompts from script...`);
    const prompts = await scriptToVideoPrompts(parsed);
    prompts.forEach((p, i) => console.log(`  Clip ${i + 1}: ${p.substring(0, 80)}...`));

    if (flags.dryRun) {
      console.log(`[DRY RUN] Skipping generation for ${id}`);
      return { id, status: 'dry-run', prompts };
    }

    // 3. Generate voiceover text + TTS (optional — only if Replicate token is set)
    let audioPath = null;
    const voiceoverText = extractVoiceover(parsed);
    if (REPLICATE_TOKEN) {
      console.log(`[3/5] Generating voiceover...`);
      if (voiceoverText) {
        try {
          console.log(`  VO text: "${voiceoverText.substring(0, 80)}..."`);
          const audioUrl = await generateTTS(voiceoverText);
          audioPath = path.join(tmpDir, 'voiceover.wav');
          await downloadFile(audioUrl, audioPath);
          console.log(`  TTS done`);
        } catch (err) {
          console.log(`  TTS failed (${err.message}), continuing without voiceover`);
        }
      }
    } else {
      console.log(`[3/5] Skipping voiceover (no REPLICATE_API_TOKEN)`);
    }

    // 4. Generate 3 video clips via fal.ai (parallel)
    console.log(`[4/5] Generating 3 video clips via fal.ai (parallel)...`);
    const clipUrls = await Promise.all(prompts.map((p, i) => {
      console.log(`  Starting clip ${i + 1}...`);
      return generateClip(p);
    }));
    console.log(`  All 3 clips generated`);

    // Download clips
    const clipPaths = [];
    for (let i = 0; i < clipUrls.length; i++) {
      const clipPath = path.join(tmpDir, `clip-${i}.mp4`);
      await downloadFile(clipUrls[i], clipPath);
      clipPaths.push(clipPath);
    }

    // 5. Merge clips + audio
    console.log(`[5/5] Merging clips + voiceover...`);
    fs.mkdirSync(OUTPUT_DIR, { recursive: true });
    const outputPath = path.join(OUTPUT_DIR, `${id}.mp4`);
    mergeClipsWithAudio(clipPaths, audioPath, outputPath);

    // Save metadata alongside video
    const metaPath = path.join(OUTPUT_DIR, `${id}.json`);
    fs.writeFileSync(metaPath, JSON.stringify({
      id,
      title: parsed.title,
      pillar: parsed.pillar,
      caption: parsed.caption,
      voiceover: voiceoverText,
      prompts,
      clipUrls,
      renderedAt: new Date().toISOString(),
    }, null, 2));

    console.log(`  OUTPUT: ${outputPath}`);

    // Update status
    status[id] = { status: 'rendered', outputPath, renderedAt: new Date().toISOString() };
    saveStatus(status);

    // Cleanup
    try { fs.rmSync(tmpDir, { recursive: true }); } catch(e) {}

    return { id, status: 'rendered', outputPath };
  } catch (err) {
    console.error(`  FAILED: ${err.message}`);
    status[id] = { status: 'failed', error: err.message, failedAt: new Date().toISOString() };
    saveStatus(status);
    try { fs.rmSync(tmpDir, { recursive: true }); } catch(e) {}
    return { id, status: 'failed', error: err.message };
  }
}

// ===== Main =====
async function main() {
  console.log('Content Video Batch Renderer');
  console.log('============================\n');

  // Validate env — only FAL_KEY is required
  if (!flags.list) {
    if (!FAL_KEY) {
      console.error('FAL_KEY is required. Set it in backend/.env');
      process.exit(1);
    }
    if (!OPENROUTER_KEY) console.log('Note: OPENROUTER_API_KEY not set — using local prompt builder (still works fine)');
    if (!REPLICATE_TOKEN) console.log('Note: REPLICATE_API_TOKEN not set — videos will render without voiceover');
  }

  const allScripts = discoverScripts();
  console.log(`Found ${allScripts.length} scripts across ${new Set(allScripts.map(s => s.week)).size} weeks\n`);

  const status = loadStatus();

  // Filter scripts
  let scripts = allScripts;
  if (flags.week) scripts = scripts.filter(s => s.week === flags.week);
  if (flags.script) scripts = scripts.filter(s => s.id.includes(flags.script));
  if (!flags.force && !flags.list) scripts = scripts.filter(s => !status[s.id] || status[s.id].status !== 'rendered');

  // --list mode
  if (flags.list) {
    console.log('Script Render Status:');
    console.log('-'.repeat(70));
    for (const s of allScripts) {
      const st = status[s.id];
      const icon = st?.status === 'rendered' ? '✅' : st?.status === 'failed' ? '❌' : '⬜';
      const info = st?.status === 'rendered' ? st.renderedAt : st?.status === 'failed' ? st.error?.substring(0, 40) : 'pending';
      console.log(`${icon} [week-${s.week}] ${s.id.padEnd(35)} ${info}`);
    }
    console.log(`\nTotal: ${allScripts.length} | Rendered: ${Object.values(status).filter(s => s.status === 'rendered').length} | Failed: ${Object.values(status).filter(s => s.status === 'failed').length} | Pending: ${allScripts.length - Object.keys(status).length}`);
    return;
  }

  if (scripts.length === 0) {
    console.log('No scripts to render. Use --force to re-render, or --list to see status.');
    return;
  }

  console.log(`Rendering ${scripts.length} script(s)...\n`);

  const results = [];
  for (const script of scripts) {
    const result = await renderScript(script, status);
    results.push(result);
    // Small delay between scripts to be kind to APIs
    if (scripts.indexOf(script) < scripts.length - 1) await delay(2000);
  }

  // Summary
  console.log(`\n${'='.repeat(60)}`);
  console.log('BATCH RENDER COMPLETE');
  console.log(`${'='.repeat(60)}`);
  const rendered = results.filter(r => r.status === 'rendered');
  const failed = results.filter(r => r.status === 'failed');
  const dryRun = results.filter(r => r.status === 'dry-run');
  console.log(`Rendered: ${rendered.length} | Failed: ${failed.length}${dryRun.length ? ` | Dry-run: ${dryRun.length}` : ''}`);
  if (failed.length) {
    console.log('\nFailed scripts:');
    failed.forEach(f => console.log(`  ${f.id}: ${f.error}`));
  }
  if (rendered.length) {
    console.log(`\nOutput directory: ${OUTPUT_DIR}`);
  }
}

main().catch(err => { console.error('Fatal:', err); process.exit(1); });
