/**
 * Reel Generator v4 — Beat-synced cinematic montage
 * Detects beats in music → cuts clips on the beat → story-driven
 */
const fs = require('fs');
const path = require('path');
const { v4: uuid } = require('uuid');
const fetch = require('node-fetch');
const { execSync } = require('child_process');

const OUTPUT_DIR = path.join(__dirname, '..', 'output');
const TEMP_DIR = path.join(__dirname, '..', 'temp');
const MUSIC_DIR = path.join(__dirname, '..', 'music');

function ensureDir(dir) {
  if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
}

/**
 * Beat Detection — analyze music audio and find beat/onset timestamps
 * Uses ffmpeg to extract audio energy, then finds peaks
 */
function detectBeats(audioPath, targetDuration, minClips = 8, maxClips = 15) {
  ensureDir(TEMP_DIR);

  // Extract raw audio volume data at 100 samples/sec using astats
  const rawFile = path.join(TEMP_DIR, `beats-${uuid()}.txt`);
  try {
    // Get volume per frame using volumedetect-style approach
    // Extract audio as raw PCM, then analyze energy in chunks
    const wavFile = path.join(TEMP_DIR, `beats-${uuid()}.wav`);
    execSync(
      `ffmpeg -y -i "${audioPath}" -t ${targetDuration} -ac 1 -ar 8000 -f wav "${wavFile}"`,
      { stdio: 'pipe', timeout: 30000 }
    );

    // Read WAV and compute energy per chunk (each chunk = 1 beat window)
    const wavData = fs.readFileSync(wavFile);
    // Skip WAV header (44 bytes), 16-bit samples
    const samples = [];
    for (let i = 44; i < wavData.length - 1; i += 2) {
      samples.push(wavData.readInt16LE(i));
    }

    if (fs.existsSync(wavFile)) fs.unlinkSync(wavFile);

    const sampleRate = 8000;
    const totalSamples = samples.length;
    const totalSeconds = totalSamples / sampleRate;

    // Compute energy in windows of ~100ms
    const windowSize = Math.floor(sampleRate * 0.1); // 800 samples = 100ms
    const energies = [];
    for (let i = 0; i < samples.length; i += windowSize) {
      const chunk = samples.slice(i, i + windowSize);
      const energy = chunk.reduce((sum, s) => sum + Math.abs(s), 0) / chunk.length;
      energies.push({ time: i / sampleRate, energy });
    }

    if (energies.length < 5) {
      console.log('[Beats] Not enough audio data, using uniform cuts');
      return uniformBeats(targetDuration, minClips);
    }

    // Compute average energy
    const avgEnergy = energies.reduce((s, e) => s + e.energy, 0) / energies.length;

    // Find onsets: energy spikes above 1.3x average with minimum gap
    const minGap = targetDuration / maxClips; // minimum time between beats
    const threshold = avgEnergy * 1.3;
    const beats = [0]; // always start at 0

    for (const e of energies) {
      if (e.energy > threshold && e.time > 0.3) {
        const lastBeat = beats[beats.length - 1];
        if (e.time - lastBeat >= minGap) {
          beats.push(parseFloat(e.time.toFixed(3)));
        }
      }
    }

    // If we got too few beats, add some at energy peaks between existing beats
    if (beats.length < minClips) {
      // Find top energy peaks not already in beats
      const sorted = [...energies]
        .filter(e => e.time > 0.3)
        .sort((a, b) => b.energy - a.energy);
      
      for (const peak of sorted) {
        if (beats.length >= minClips) break;
        const tooClose = beats.some(b => Math.abs(b - peak.time) < minGap);
        if (!tooClose) {
          beats.push(parseFloat(peak.time.toFixed(3)));
        }
      }
      beats.sort((a, b) => a - b);
    }

    // Trim to maxClips if too many
    while (beats.length > maxClips) {
      // Remove the beat with smallest gap to its neighbor
      let minIdx = 1;
      let minDiff = Infinity;
      for (let i = 1; i < beats.length - 1; i++) {
        const diff = beats[i + 1] - beats[i];
        if (diff < minDiff) { minDiff = diff; minIdx = i; }
      }
      beats.splice(minIdx, 1);
    }

    // Add end marker
    beats.push(targetDuration);

    // Compute durations
    const segments = [];
    for (let i = 0; i < beats.length - 1; i++) {
      segments.push({
        start: beats[i],
        duration: parseFloat((beats[i + 1] - beats[i]).toFixed(3))
      });
    }

    console.log(`[Beats] Detected ${segments.length} beats: ${segments.map(s => s.duration.toFixed(2) + 's').join(', ')}`);
    return segments;

  } catch (err) {
    console.log(`[Beats] Detection failed: ${err.message}, using uniform cuts`);
    return uniformBeats(targetDuration, minClips);
  }
}

/**
 * Fallback: uniform beat distribution
 */
function uniformBeats(totalDuration, clipCount) {
  const dur = totalDuration / clipCount;
  const segments = [];
  for (let i = 0; i < clipCount; i++) {
    segments.push({ start: parseFloat((i * dur).toFixed(3)), duration: parseFloat(dur.toFixed(3)) });
  }
  return segments;
}

/**
 * Step 1: AI writes scenario — 10-15 fast cuts with search queries + text overlay
 */
async function generateScenario(topic, language = 'en', duration = 15, clipCount = 10) {
  clipCount = Math.max(5, clipCount);
  const langMap = { en: 'English', ru: 'Russian', es: 'Spanish', de: 'German', fr: 'French', pt: 'Portuguese', he: 'Hebrew', ar: 'Arabic' };
  const lang = langMap[language] || 'English';

  const res = await fetch('https://openrouter.ai/api/v1/chat/completions', {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${process.env.OPENROUTER_API_KEY}`,
      'Content-Type': 'application/json'
    },
    body: JSON.stringify({
      model: 'google/gemini-2.0-flash-001',
      messages: [{
        role: 'user',
        content: `You are a viral Instagram Reels ad director. You follow a STRICT video ad formula.

VIDEO AD FORMULA (follow this EXACTLY):
━━━ ACT 1: THE PROBLEM (0-2s) — 2-3 clips ━━━
Show the pain/frustration. Make the viewer feel it instantly.
Visuals: frustrated person, messy situation, chaos, struggle
Text: short punchy pain point ("This again?", "So frustrating", "Why is this so hard?")

━━━ ACT 2: THE SOLUTION (2-6s) — 3-4 clips ━━━
Show the product/service fixing the problem. The "aha" moment.
Visuals: discovery moment, phone/product in use, transformation happening
Text: reveal the fix ("Then I found this", "One click", "Game changer")

━━━ ACT 3: THE RESULT (6-10s) — 3-4 clips ━━━
Show the beautiful outcome. Close-ups of the result. Happy customer.
Visuals: close-up product/result, person smiling, lifestyle upgrade, before/after
Text: show the win ("Perfect", "Finally", "This is it", "Life changed")

━━━ ACT 4: CTA (10-15s) — 2-3 clips ━━━
Brand name, call to action, urgency.
Visuals: aesthetic product shot, lifestyle aspiration, bright/clean
Text: brand name + CTA ("Get yours today", "Link in bio", "Try it free", website URL)

Topic: "${topic}"
Language for ALL text: ${lang}
Duration: ${duration} seconds
Total clips: ${clipCount}

RULES:
1. Follow the 4-ACT formula STRICTLY
2. Text: 2-5 words per clip, punchy, emotional
3. Visuals: search for REAL Pexels footage. NO brand names in search queries. Use generic cinematic searches
4. Visuals should COMPLEMENT the text mood, not literally illustrate it
5. Each search query MUST be different — mix close-ups, wide shots, people, products, environments
6. Make it feel like a polished ad, not a stock video slideshow

Pick ONE musicMood:
- "dark" — dramatic, intense (tech, thriller, edgy brands)
- "hype" — energetic, fast (sports, streetwear, launches)
- "chill" — calm, soft (skincare, wellness, food)
- "motivational" — inspiring (career, fitness, self-improvement)
- "cinematic" — epic, beautiful (travel, luxury, lifestyle)

Reply ONLY with JSON:
{
  "musicMood": "dark|hype|chill|motivational|cinematic",
  "clips": [
    {
      "search": "pexels search query (English, specific, cinematic, NO brand names)",
      "text": "overlay text in ${lang}"
    },
    ... (${clipCount} clips, following the 4-act formula)
  ]
}`
      }],
      temperature: 0.9,
      max_tokens: 800
    })
  });

  const data = await res.json();
  const content = data.choices?.[0]?.message?.content || '';
  const jsonMatch = content.match(/\{[\s\S]*\}/);
  if (!jsonMatch) throw new Error('AI scenario parse failed: ' + content.substring(0, 200));
  const parsed = JSON.parse(jsonMatch[0]);
  
  // Normalize: ensure clips have both search and text
  if (parsed.clips) {
    parsed.clips = parsed.clips.map(c => {
      if (typeof c === 'string') return { search: c, text: '' };
      return { search: c.search || '', text: c.text || '' };
    });
  }
  return parsed;
}

/**
 * Step 2: Find stock videos from Pexels — NO people, always vertical/portrait
 */
async function findClips(searchQueries) {
  const results = [];
  const usedVideoIds = new Set();

  for (const query of searchQueries) {
    // Add "no people" to searches
    const searchQ = query.includes('people') ? query : `${query}`;

    const res = await fetch(
      `https://api.pexels.com/videos/search?query=${encodeURIComponent(searchQ)}&orientation=portrait&size=medium&per_page=15`,
      { headers: { Authorization: process.env.PEXELS_API_KEY } }
    );
    const data = await res.json();
    let videos = (data.videos || []).filter(v => !usedVideoIds.has(v.id) && v.duration >= 3);

    // Fallback with simpler query
    if (!videos.length) {
      const fallbackQ = query.split(' ').slice(0, 3).join(' ') + ' nature';
      const res2 = await fetch(
        `https://api.pexels.com/videos/search?query=${encodeURIComponent(fallbackQ)}&orientation=portrait&per_page=15`,
        { headers: { Authorization: process.env.PEXELS_API_KEY } }
      );
      const data2 = await res2.json();
      videos = (data2.videos || []).filter(v => !usedVideoIds.has(v.id) && v.duration >= 2);
    }

    if (!videos.length) {
      console.log(`[Reel] ⚠ No footage for: ${query}, skipping`);
      continue;
    }

    // Pick random from top
    const video = videos[Math.floor(Math.random() * Math.min(videos.length, 5))];
    usedVideoIds.add(video.id);

    // Prefer vertical HD
    const file = video.video_files
      .filter(f => f.height >= 720 && f.height > f.width)
      .sort((a, b) => b.height - a.height)[0]
      || video.video_files.sort((a, b) => b.height - a.height)[0];

    results.push({ url: file.link, width: file.width, height: file.height, duration: video.duration });
  }

  return results;
}

/**
 * Analyze a music track's energy level (0-1 scale)
 * High energy = hype/upbeat, Low energy = chill/ambient
 */
function analyzeTrackEnergy(audioPath) {
  try {
    const wavFile = path.join(TEMP_DIR, `analyze-${uuid()}.wav`);
    execSync(`ffmpeg -y -i "${audioPath}" -ac 1 -ar 8000 -f wav "${wavFile}"`, { stdio: 'pipe', timeout: 15000 });
    const wavData = fs.readFileSync(wavFile);
    const samples = [];
    for (let i = 44; i < wavData.length - 1; i += 2) {
      samples.push(Math.abs(wavData.readInt16LE(i)));
    }
    if (fs.existsSync(wavFile)) fs.unlinkSync(wavFile);
    if (samples.length === 0) return 0.5;
    
    const avg = samples.reduce((s, v) => s + v, 0) / samples.length;
    const max = Math.max(...samples.slice(0, 10000)); // sample first chunk
    const energy = avg / (max || 1); // 0-1 normalized
    
    // Also check variance (rhythmic = more variance)
    const variance = samples.slice(0, 10000).reduce((s, v) => s + Math.pow(v - avg, 2), 0) / Math.min(samples.length, 10000);
    const rhythm = Math.min(1, Math.sqrt(variance) / (max || 1));
    
    return { energy: parseFloat(energy.toFixed(3)), rhythm: parseFloat(rhythm.toFixed(3)) };
  } catch (e) {
    return { energy: 0.5, rhythm: 0.5 };
  }
}

/**
 * Map AI mood to energy/rhythm target
 */
function moodToTarget(mood) {
  const m = (mood || '').toLowerCase();
  if (m.includes('dark') || m.includes('dramatic') || m.includes('intense') || m.includes('epic'))
    return { energy: 0.7, rhythm: 0.8, label: 'dark' };
  if (m.includes('hype') || m.includes('upbeat') || m.includes('energetic') || m.includes('pop') || m.includes('hip'))
    return { energy: 0.8, rhythm: 0.9, label: 'hype' };
  if (m.includes('chill') || m.includes('lofi') || m.includes('lo-fi') || m.includes('ambient') || m.includes('calm'))
    return { energy: 0.3, rhythm: 0.3, label: 'chill' };
  if (m.includes('motivat') || m.includes('uplift') || m.includes('inspir'))
    return { energy: 0.6, rhythm: 0.6, label: 'motivational' };
  if (m.includes('cinematic') || m.includes('piano') || m.includes('orchestral'))
    return { energy: 0.5, rhythm: 0.5, label: 'cinematic' };
  if (m.includes('electronic') || m.includes('edm') || m.includes('house'))
    return { energy: 0.7, rhythm: 0.9, label: 'hype' };
  return { energy: 0.5, rhythm: 0.5, label: 'cinematic' };
}

/**
 * Step 3: Find music matching the mood
 */
async function findMusic(musicMood, targetDuration = 15) {
  ensureDir(MUSIC_DIR);
  ensureDir(TEMP_DIR);

  const target = moodToTarget(musicMood);
  console.log(`[Music] Looking for "${musicMood}" → target: ${target.label} (energy=${target.energy}, rhythm=${target.rhythm})`);

  // Match by filename mood tag + duration
  const cached = fs.readdirSync(MUSIC_DIR).filter(f => f.endsWith('.mp3') || f.endsWith('.m4a') || f.endsWith('.aac'));
  
  if (cached.length > 0) {
    // Tag each file by its name prefix
    const tagged = cached.map(file => {
      const name = file.toLowerCase();
      let tag = 'cinematic'; // default
      if (name.startsWith('dark-') || name.includes('dark') || name.includes('cinematic.edit')) tag = 'dark';
      else if (name.startsWith('hype-') || name.includes('hype') || name.includes('skateboard') || name.includes('street')) tag = 'hype';
      else if (name.startsWith('chill-') || name.includes('chill') || name.includes('lofi') || name.includes('aesthetic')) tag = 'chill';
      else if (name.startsWith('motivational-') || name.includes('motiv') || name.includes('inspir')) tag = 'motivational';
      else if (name.includes('earth') || name.includes('natgeo') || name.includes('beautiful') || name.includes('travel')) tag = 'cinematic';
      
      let dur = 0;
      try {
        dur = parseFloat(execSync(`ffprobe -v quiet -show_entries format=duration -of csv=p=0 "${path.join(MUSIC_DIR, file)}"`, { stdio: 'pipe', timeout: 5000 }).toString().trim());
      } catch (e) {}
      
      return { file, tag, dur, fullPath: path.join(MUSIC_DIR, file) };
    }).filter(t => t.dur >= targetDuration * 0.5); // must be long enough

    // Mood mapping — which tags match which AI moods
    const moodMap = {
      'dark': ['dark', 'cinematic'],
      'hype': ['hype', 'motivational'],
      'chill': ['chill', 'cinematic'],
      'motivational': ['motivational', 'hype', 'cinematic'],
      'cinematic': ['cinematic', 'dark', 'chill'],
    };

    const preferredTags = moodMap[target.label] || ['cinematic'];
    
    // Find best match: exact tag first, then fallback tags
    let matches = [];
    for (const pref of preferredTags) {
      const tagMatches = tagged.filter(t => t.tag === pref);
      if (tagMatches.length > 0) {
        matches = tagMatches;
        break;
      }
    }
    
    // If no tag match at all, use anything
    if (matches.length === 0) matches = tagged;
    
    // Prefer tracks that are close to target duration (not too long)
    matches.sort((a, b) => {
      const aDiff = Math.abs(a.dur - targetDuration);
      const bDiff = Math.abs(b.dur - targetDuration);
      return aDiff - bDiff;
    });

    // Pick random from top 3 matches for variety
    const pool = matches.slice(0, Math.min(3, matches.length));
    const pick = pool[Math.floor(Math.random() * pool.length)];
    console.log(`[Music] Mood "${target.label}" → tag "${pick.tag}" → ${pick.file} (${pick.dur.toFixed(1)}s)`);
    return pick.fullPath;
  }

  // Try Apify to get audio from reels
  if (process.env.APIFY_API_KEY) {
    try {
      // Scrape a few travel/cinematic reels for their audio
      const searches = ['cinematic travel reels', 'aesthetic nature reels', 'viral travel montage'];
      const searchQ = searches[Math.floor(Math.random() * searches.length)];

      console.log(`[Reel] Scraping reel audio via Apify...`);
      const runRes = await fetch(
        `https://api.apify.com/v2/acts/apify~instagram-reel-scraper/runs?waitForFinish=90`,
        {
          method: 'POST',
          headers: {
            'Authorization': `Bearer ${process.env.APIFY_API_KEY}`,
            'Content-Type': 'application/json'
          },
          body: JSON.stringify({ username: ['travel', 'nature', 'earthpix'], resultsLimit: 5 })
        }
      );

      const runData = await runRes.json();
      const datasetId = runData?.data?.defaultDatasetId;

      if (datasetId) {
        const itemsRes = await fetch(
          `https://api.apify.com/v2/datasets/${datasetId}/items?format=json`,
          { headers: { 'Authorization': `Bearer ${process.env.APIFY_API_KEY}` } }
        );
        const items = await itemsRes.json();

        for (const item of (Array.isArray(items) ? items : [])) {
          const audioUrl = item.audioUrl || item.musicInfo?.audioUrl;
          if (audioUrl) {
            const ext = audioUrl.includes('.mp3') ? '.mp3' : '.m4a';
            const audioPath = path.join(MUSIC_DIR, `music-${uuid()}${ext}`);
            const audioRes = await fetch(audioUrl);
            if (audioRes.ok) {
              const buf = await audioRes.buffer();
              if (buf.length > 10000) { // at least 10KB
                fs.writeFileSync(audioPath, buf);
                console.log(`[Reel] ✅ Downloaded reel music: ${(buf.length/1024).toFixed(0)}KB`);
                return audioPath;
              }
            }
          }
        }
      }
    } catch (err) {
      console.log(`[Reel] Apify music failed: ${err.message}`);
    }
  }

  // Fallback: try Pixabay music API
  if (process.env.PIXABAY_API_KEY) {
    try {
      const moods = { 'cinematic': 'cinematic', 'chill': 'chill', 'dark': 'dark', 'upbeat': 'upbeat', 'ambient': 'ambient' };
      const q = moods[musicMood?.toLowerCase()] || 'cinematic';
      const res = await fetch(`https://pixabay.com/api/?key=${process.env.PIXABAY_API_KEY}&q=${q}&media_type=music&per_page=5`);
      // Pixabay doesn't have a music API via the standard endpoint, skip
    } catch (err) {}
  }

  console.log('[Reel] No music source available');
  return null;
}

/**
 * Step 4: Download all clips in parallel batches
 */
async function downloadClips(clips) {
  const paths = [];
  // Download in batches of 4
  for (let i = 0; i < clips.length; i += 4) {
    const batch = clips.slice(i, i + 4);
    const batchPaths = await Promise.all(batch.map(async (clip, j) => {
      const p = path.join(TEMP_DIR, `clip-${i + j}-${uuid()}.mp4`);
      const res = await fetch(clip.url);
      const buf = await res.buffer();
      fs.writeFileSync(p, buf);
      return p;
    }));
    paths.push(...batchPaths);
  }
  return paths;
}

/**
 * Step 5: Process each clip — random 1-1.5s cut, scale to 9:16, cinematic grade
 */
function processClip(inputPath, outputPath, clipDuration, sourceDuration, clipText) {
  const stripEmoji = (t) => (t || '').replace(/[\u{1F000}-\u{1FFFF}|\u{2600}-\u{27BF}|\u{FE00}-\u{FE0F}|\u{1F900}-\u{1F9FF}|\u{200D}|\u{20E3}|\u{E0020}-\u{E007F}]/gu, '').trim();
  const escDraw = (t) => stripEmoji(t).replace(/\\/g, '\\\\').replace(/'/g, "'\\''").replace(/:/g, '\\:');

  // Random start point
  const maxStart = Math.max(0, sourceDuration - clipDuration - 1);
  const startOffset = Math.floor(Math.random() * maxStart);
  const fontBold = '/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf';

  // Cinematic look + per-clip text
  const filters = [
    'scale=1080:1920:force_original_aspect_ratio=increase',
    'crop=1080:1920',
    'eq=brightness=-0.04:contrast=1.1:saturation=0.9',
    'fade=t=in:st=0:d=0.15',
    `fade=t=out:st=${clipDuration - 0.15}:d=0.15`
  ];

  const text = escDraw(clipText);
  if (text) {
    filters.push(
      `drawtext=text='${text}':fontfile='${fontBold}':fontsize=58:fontcolor=white:shadowcolor=black@0.9:shadowx=3:shadowy=3:x=(w-text_w)/2:y=(h*0.45):line_spacing=10`
    );
  }

  execSync(
    `ffmpeg -y -ss ${startOffset} -t ${clipDuration} -i "${inputPath}" -vf "${filters.join(',')}" -c:v libx264 -preset fast -crf 22 -an -pix_fmt yuv420p -r 30 "${outputPath}"`,
    { stdio: 'pipe', timeout: 30000 }
  );
}

/**
 * Step 6: Assemble — concat clips + text overlay + music
 */
function assembleReel(clipPaths, outputPath, { musicPath, totalDuration }) {
  // Concat all clips (text already burned in)
  const listFile = path.join(TEMP_DIR, `concat-${uuid()}.txt`);
  fs.writeFileSync(listFile, clipPaths.map(p => `file '${p}'`).join('\n'));

  const tempConcat = path.join(TEMP_DIR, `concat-${uuid()}.mp4`);
  execSync(`ffmpeg -y -f concat -safe 0 -i "${listFile}" -c:v libx264 -preset fast -crf 22 -pix_fmt yuv420p "${tempConcat}"`, { stdio: 'pipe', timeout: 120000 });

  // Add music
  if (musicPath && fs.existsSync(musicPath)) {
    try {
      execSync(
        `ffmpeg -y -i "${tempConcat}" -i "${musicPath}" -filter_complex "[1:a]afade=t=in:d=0.5,afade=t=out:st=${Math.max(1, totalDuration - 1.5)}:d=1.5,volume=0.75[a]" -map 0:v -map "[a]" -c:v copy -c:a aac -b:a 192k -shortest -movflags +faststart "${outputPath}"`,
        { stdio: 'pipe', timeout: 120000 }
      );
    } catch (err) {
      execSync(`ffmpeg -y -i "${tempConcat}" -c:v copy -an -movflags +faststart "${outputPath}"`, { stdio: 'pipe', timeout: 30000 });
    }
  } else {
    execSync(`ffmpeg -y -i "${tempConcat}" -c:v copy -an -movflags +faststart "${outputPath}"`, { stdio: 'pipe', timeout: 30000 });
  }

  // Cleanup
  [listFile, tempConcat].forEach(f => { try { fs.unlinkSync(f); } catch(e) {} });
}

/**
 * Main entry — beat-synced pipeline
 * 1. Find music first
 * 2. Detect beats in music → get exact cut timestamps
 * 3. AI scenario with exact clip count matching beats
 * 4. Find & download stock footage
 * 5. Cut each clip to its beat duration
 * 6. Assemble with music
 */
async function generateReel({ topic, language = 'en', duration = 15 }) {
  ensureDir(OUTPUT_DIR);
  ensureDir(TEMP_DIR);
  ensureDir(MUSIC_DIR);

  const startTime = Date.now();

  // 1. Quick AI pre-pass — just get the mood to pick the right music
  console.log(`[Reel] Step 1: Getting mood for music selection...`);
  const preScenario = await generateScenario(topic, language, duration, 10);
  const mood = preScenario.musicMood || 'cinematic';

  // 2. Find music matching the mood
  console.log(`[Reel] Step 2: Finding "${mood}" music...`);
  const musicPath = await findMusic(mood, duration);

  // 3. Detect beats in the chosen music
  let beatSegments;
  if (musicPath) {
    console.log(`[Reel] Step 3: Detecting beats...`);
    beatSegments = detectBeats(musicPath, duration, 8, 15);
  } else {
    console.log(`[Reel] Step 3: No music, uniform cuts`);
    beatSegments = uniformBeats(duration, 10);
  }

  const clipCount = beatSegments.length;
  console.log(`[Reel] Beat segments: ${clipCount} cuts → ${beatSegments.map(s => s.duration.toFixed(2) + 's').join(' | ')}`);

  // Use the pre-generated scenario (already has the right clip count roughly)
  const scenario = preScenario;

  let clips = (scenario.clips || []);
  // Pad or trim to match beat count
  while (clips.length < clipCount) {
    clips.push({ search: clips[clips.length - 1]?.search || 'cinematic landscape', text: '' });
  }
  clips = clips.slice(0, clipCount);

  console.log(`[Reel] Music mood: ${scenario.musicMood}`);
  clips.forEach((c, i) => console.log(`  [${i}] ${beatSegments[i].duration.toFixed(2)}s | "${c.text}" → ${c.search}`));

  // 4. Find & download stock footage
  const searchQueries = clips.map(c => c.search);
  console.log(`[Reel] Step 4: Finding ${clips.length} stock clips...`);
  const stockClips = await findClips(searchQueries);

  if (stockClips.length < 5) throw new Error(`Only found ${stockClips.length} clips, need at least 5`);

  // Adjust if we got fewer clips than beats
  while (beatSegments.length > stockClips.length) {
    // Merge last two segments
    const last = beatSegments.pop();
    beatSegments[beatSegments.length - 1].duration += last.duration;
  }

  console.log(`[Reel] Step 5: Downloading ${stockClips.length} clips...`);
  const clipPaths = await downloadClips(stockClips);

  // 5. Process each clip with its beat-matched duration
  console.log(`[Reel] Step 6: Rendering ${clipPaths.length} clips (beat-synced)...`);
  const processedPaths = [];

  for (let i = 0; i < clipPaths.length; i++) {
    const outClip = path.join(TEMP_DIR, `proc-${i}-${uuid()}.mp4`);
    const beatDur = beatSegments[i]?.duration || 1.2;
    const clipText = clips[i]?.text || '';
    processClip(clipPaths[i], outClip, beatDur, stockClips[i].duration, clipText);
    processedPaths.push(outClip);
  }

  // 6. Assemble with music
  const outputFile = path.join(OUTPUT_DIR, `reel-${uuid()}.mp4`);
  const totalDur = beatSegments.reduce((s, b) => s + b.duration, 0);
  console.log(`[Reel] Step 7: Assembling ${totalDur.toFixed(1)}s reel (${processedPaths.length} clips, beat-synced)...`);
  assembleReel(processedPaths, outputFile, { musicPath, totalDuration: totalDur });

  // Cleanup
  [...clipPaths, ...processedPaths].forEach(f => { try { fs.unlinkSync(f); } catch(e) {} });

  const elapsed = ((Date.now() - startTime) / 1000).toFixed(1);
  const fileSize = (fs.statSync(outputFile).size / 1024 / 1024).toFixed(1);
  console.log(`[Reel] ✅ Done: ${elapsed}s | ${fileSize}MB | ${processedPaths.length} clips | beat-synced: ${musicPath ? 'yes' : 'no'}`);

  return {
    file: outputFile,
    clipCount: processedPaths.length,
    beatSegments: beatSegments.map(s => s.duration.toFixed(2) + 's'),
    musicMood: scenario.musicMood,
    hasMusic: !!musicPath,
    duration: totalDur,
    renderTime: elapsed,
    fileSize: fileSize + 'MB'
  };
}

module.exports = { generateReel, generateScenario, findClips, findMusic, detectBeats };
