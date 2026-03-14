/**
 * /api/ads — AI Ad Maker v4
 *
 * Dual-provider: fal.ai (video via PixVerse v4) + Replicate (TTS)
 * Flow: URL → scrape → script → TTS (Replicate) → 3 video clips (fal.ai parallel) → ffmpeg merge
 */
const express = require('express');
const router = express.Router();
const { v4: uuid } = require('uuid');
const { execSync } = require('child_process');
const fs = require('fs');
const path = require('path');
const os = require('os');
const { fal } = require('@fal-ai/client');

const { OPERATION_CREDITS } = require('../config/credits');
const REPLICATE_TOKEN = process.env.REPLICATE_API_TOKEN || '';
const OPENROUTER_KEY = process.env.OPENROUTER_API_KEY || '';
const FAL_KEY = process.env.FAL_KEY || '';

fal.config({ credentials: FAL_KEY });

const TTS_MODEL = 'minimax/speech-02-hd';
const FAL_VIDEO_MODEL = 'fal-ai/pixverse/v4/text-to-video';

const delay = ms => new Promise(r => setTimeout(r, ms));

// Voice per language (MiniMax Speech-02-HD)
const VOICES = {
  en: { voice_id: 'English_CaptivatingStoryteller', lang: 'English' },
  ru: { voice_id: 'Russian_AmbitiousWoman', lang: 'Russian' },
  es: { voice_id: 'Spanish_CaptivatingStoryteller', lang: 'Spanish' },
  fr: { voice_id: 'French_MovieLeadFemale', lang: 'French' },
  de: { voice_id: 'German_SweetLady', lang: 'German' },
};

// ===== Replicate (TTS only) =====
async function replicatePost(urlPath, body, retries = 5) {
  for (let attempt = 0; attempt <= retries; attempt++) {
    const res = await fetch(`https://api.replicate.com${urlPath}`, {
      method: 'POST',
      headers: { 'Authorization': `Bearer ${REPLICATE_TOKEN}`, 'Content-Type': 'application/json' },
      body: JSON.stringify(body),
    });
    const data = await res.json();
    if (res.status === 429 && attempt < retries) {
      const wait = Math.max(10, parseInt(res.headers.get('retry-after') || '10'));
      console.log(`[Ad] Rate limited, waiting ${wait}s (attempt ${attempt + 1})...`);
      await delay(wait * 1000);
      continue;
    }
    return data;
  }
}

async function replicateGet(urlPath) {
  const res = await fetch(`https://api.replicate.com${urlPath}`, {
    headers: { 'Authorization': `Bearer ${REPLICATE_TOKEN}` },
  });
  return res.json();
}

async function pollReplicate(id, maxWait = 120000) {
  const start = Date.now();
  while (Date.now() - start < maxWait) {
    const pred = await replicateGet(`/v1/predictions/${id}`);
    if (pred.status === 'succeeded') return pred;
    if (pred.status === 'failed' || pred.status === 'canceled')
      throw new Error(`Replicate ${id} ${pred.status}: ${pred.error || 'unknown'}`);
    await delay(3000);
  }
  throw new Error(`Replicate TTS timed out`);
}

// ===== fal.ai (video) =====
async function falGenerate(prompt) {
  const result = await fal.subscribe(FAL_VIDEO_MODEL, {
    input: { prompt, duration: '5', aspect_ratio: '9:16', quality: 'high' },
    logs: false,
    pollInterval: 5000,
  });
  const data = result.data;
  if (data?.video?.url) return data.video.url;
  throw new Error(`fal.ai no video URL: ${JSON.stringify(data).substring(0, 200)}`);
}

// ===== Script generation =====
async function generateScript(productInfo, userNotes, langName = 'English') {
  const res = await fetch('https://openrouter.ai/api/v1/chat/completions', {
    method: 'POST',
    headers: { 'Authorization': `Bearer ${OPENROUTER_KEY}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({
      model: 'google/gemini-2.0-flash-001',
      messages: [{ role: 'user', content: `You are a viral short-form video scriptwriter. Write a 15-second voiceover script for a product ad video.

LANGUAGE: Write the ENTIRE script in ${langName}. Every word must be in ${langName}.

Product: ${productInfo.title || 'Unknown product'}
Description: ${productInfo.description || 'N/A'}
Website: ${productInfo.domain || 'N/A'}
${userNotes ? `Creative direction: ${userNotes}` : ''}

STRICT RULES:
- Output ONLY the spoken words in ${langName}. Nothing else.
- Do NOT include stage directions, notes, labels, or formatting
- Do NOT repeat or paraphrase the creative direction
- About 40-50 words (15 seconds when spoken)
- Start with a punchy hook
- Mention 1-2 key benefits naturally
- End with a clear call to action
- Conversational, energetic, authentic tone` }],
      max_tokens: 200,
    }),
  });
  const data = await res.json();
  let script = data.choices?.[0]?.message?.content?.trim() || '';
  return script.replace(/^["']|["']$/g, '').trim() || 'Stay protected online. Get your VPN today.';
}

async function generateVideoPrompts(productInfo, script) {
  const res = await fetch('https://openrouter.ai/api/v1/chat/completions', {
    method: 'POST',
    headers: { 'Authorization': `Bearer ${OPENROUTER_KEY}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({
      model: 'google/gemini-2.0-flash-001',
      messages: [{ role: 'user', content: `Generate exactly 3 short cinematic video prompts for an AI video model. These 3 clips will be edited together into one product ad.

Product: ${productInfo.title || 'tech product'}
Voiceover: "${script}"

Each prompt = DIFFERENT visual scene:
1. HOOK — dramatic, eye-catching opening that grabs attention in 2 seconds
2. BENEFIT — showing the product value visually (security, speed, freedom)
3. CTA — confident person or powerful visual ending, call to action energy

Rules:
- 1-2 sentences each, very descriptive and cinematic
- Dark moody lighting, neon accents, cyberpunk/tech aesthetic where appropriate
- Real people, real settings — no cartoon, no greenscreen
- Vertical 9:16 framing
- Each scene must be VISUALLY DIFFERENT (different setting, angle, mood)
- Output ONLY 3 prompts, numbered 1. 2. 3.` }],
      max_tokens: 400,
    }),
  });
  const data = await res.json();
  const text = data.choices?.[0]?.message?.content?.trim() || '';
  const prompts = text.split('\n').map(l => l.replace(/^\d+[\.\)]\s*/, '').trim()).filter(l => l.length > 10);
  while (prompts.length < 3) prompts.push('A person looking at their phone with a satisfied smile, dramatic lighting, cinematic vertical shot');
  return prompts.slice(0, 3);
}

// ===== File helpers =====
async function downloadFile(url, filepath) {
  const res = await fetch(url);
  fs.writeFileSync(filepath, Buffer.from(await res.arrayBuffer()));
}

function mergeVideosWithAudio(videoPaths, audioPath, outputPath) {
  const concatFile = outputPath + '.txt';
  fs.writeFileSync(concatFile, videoPaths.map(p => `file '${p}'`).join('\n'));
  const audioDur = execSync(`ffprobe -v error -show_entries format=duration -of csv=p=0 "${audioPath}"`).toString().trim();
  execSync(`ffmpeg -y -f concat -safe 0 -i "${concatFile}" -i "${audioPath}" -c:v libx264 -c:a aac -map 0:v:0 -map 1:a:0 -t ${audioDur} -shortest -pix_fmt yuv420p -movflags +faststart "${outputPath}" 2>/dev/null`);
  fs.unlinkSync(concatFile);
}

// ===== Routes =====
router.post('/generate', async (req, res) => {
  try {
    const { url, notes, userId, language = 'en' } = req.body;
    if (!url) return res.status(400).json({ error: 'url is required' });
    const voice = VOICES[language] || VOICES.en;

    const adCost = OPERATION_CREDITS['ad-maker'];
    if (userId) {
      const userCheck = await req.db.query('SELECT credits, is_subscribed FROM users WHERE external_id = $1', [userId]);
      const user = userCheck.rows[0];
      if (user && !user.is_subscribed) {
        if (user.credits < adCost) return res.status(402).json({ error: 'Insufficient credits', credits: user.credits, cost: adCost });
        await req.db.query('UPDATE users SET credits = credits - $1 WHERE external_id = $2', [adCost, userId]);
      }
    }

    const id = uuid();
    await req.db.query(
      `INSERT INTO ad_generations (id, user_id, product_url, notes, status, step, created_at) VALUES ($1, $2, $3, $4, 'processing', 'scraping', NOW())`,
      [id, userId || null, url, notes || null]
    );
    res.json({ success: true, id, status: 'processing', step: 'scraping' });

    // Background pipeline
    (async () => {
      const tmpDir = path.join(os.tmpdir(), `ad-${id}`);
      fs.mkdirSync(tmpDir, { recursive: true });

      try {
        // Step 1: Scrape
        console.log(`[Ad] ${id} Scraping...`);
        const scrapeRes = await fetch('http://127.0.0.1:3001/api/generate/preview', {
          method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ url }),
        });
        const productInfo = (await scrapeRes.json()).preview || {};
        await req.db.query(`UPDATE ad_generations SET step='script', product_info=$1 WHERE id=$2`, [JSON.stringify(productInfo), id]);

        // Step 2: Script + video prompts in parallel
        console.log(`[Ad] ${id} Script + prompts...`);
        const script = await generateScript(productInfo, notes, voice.lang);
        console.log(`[Ad] ${id} Script: "${script}"`);
        const videoPrompts = await generateVideoPrompts(productInfo, script);
        console.log(`[Ad] ${id} Prompts:`, videoPrompts);
        await req.db.query(`UPDATE ad_generations SET step='tts', script=$1 WHERE id=$2`, [script, id]);

        // Step 3: TTS (Replicate) + 3 video clips (fal.ai) ALL IN PARALLEL
        console.log(`[Ad] ${id} TTS + 3 videos in parallel...`);
        const [ttsResult, ...videoUrls] = await Promise.all([
          // TTS on Replicate
          (async () => {
            const ttsPred = await replicatePost(`/v1/models/${TTS_MODEL}/predictions`, {
              input: { text: script, voice_id: voice.voice_id, speed: 1.1, emotion: 'happy' },
            });
            if (!ttsPred.id) throw new Error(`TTS failed: ${JSON.stringify(ttsPred).substring(0, 200)}`);
            const result = await pollReplicate(ttsPred.id, 60000);
            return result.output;
          })(),
          // 3 videos on fal.ai (parallel, no rate limits!)
          falGenerate(videoPrompts[0]),
          falGenerate(videoPrompts[1]),
          falGenerate(videoPrompts[2]),
        ]);

        const audioUrl = ttsResult;
        console.log(`[Ad] ${id} TTS done + 3 clips done`);
        await req.db.query(`UPDATE ad_generations SET step='merging', audio_url=$1, video_url=$2 WHERE id=$3`, [audioUrl, videoUrls[0], id]);

        // Step 4: Download + merge
        console.log(`[Ad] ${id} Downloading & merging...`);
        const audioPath = path.join(tmpDir, 'audio.wav');
        await downloadFile(audioUrl, audioPath);

        const videoPaths = [];
        for (let i = 0; i < videoUrls.length; i++) {
          const vp = path.join(tmpDir, `clip${i}.mp4`);
          await downloadFile(videoUrls[i], vp);
          videoPaths.push(vp);
        }

        const outputPath = path.join(tmpDir, 'final.mp4');
        mergeVideosWithAudio(videoPaths, audioPath, outputPath);

        const publicPath = `/tmp/ad-${id}-final.mp4`;
        fs.copyFileSync(outputPath, publicPath);

        const outputData = JSON.stringify({ clips: videoUrls, audio: audioUrl, download: `/api/ads/download/${id}` });
        await req.db.query(`UPDATE ad_generations SET status='succeeded', step='done', output_url=$1, completed_at=NOW() WHERE id=$2`, [outputData, id]);
        console.log(`[Ad] ${id} ✅ DONE`);
        try { fs.rmSync(tmpDir, { recursive: true }); } catch(e) {}

      } catch (err) {
        console.error(`[Ad] ${id} FAILED:`, err.message);
        await req.db.query(`UPDATE ad_generations SET status='failed', error=$1, completed_at=NOW() WHERE id=$2`, [err.message, id]);
        try { fs.rmSync(tmpDir, { recursive: true }); } catch(e) {}
      }
    })();
  } catch (err) {
    console.error('[Ad] Error:', err.message);
    res.status(500).json({ error: err.message });
  }
});

router.get('/status/:id', async (req, res) => {
  try {
    const result = await req.db.query('SELECT * FROM ad_generations WHERE id = $1', [req.params.id]);
    if (!result.rows.length) return res.status(404).json({ error: 'Not found' });
    const gen = result.rows[0];
    let output = null;
    try { output = gen.output_url ? JSON.parse(gen.output_url) : null; } catch(e) { output = gen.output_url; }
    res.json({ id: gen.id, status: gen.status, step: gen.step, script: gen.script, audioUrl: gen.audio_url, videoUrl: gen.video_url, output, error: gen.error, createdAt: gen.created_at, completedAt: gen.completed_at });
  } catch (err) { res.status(500).json({ error: err.message }); }
});

router.get('/download/:id', (req, res) => {
  const filepath = `/tmp/ad-${req.params.id}-final.mp4`;
  if (fs.existsSync(filepath)) { res.setHeader('Content-Type', 'video/mp4'); res.sendFile(filepath); }
  else res.status(404).json({ error: 'Video not found or expired' });
});

module.exports = router;
