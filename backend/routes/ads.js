/**
 * /api/ads — AI Ad Maker
 *
 * Flow: URL → scrape → script → TTS → video → lip-sync
 * 
 * POST /api/ads/generate  → Start full pipeline
 * GET  /api/ads/status/:id → Poll progress
 */
const express = require('express');
const router = express.Router();
const { v4: uuid } = require('uuid');

const { OPERATION_CREDITS } = require('../config/credits');
const REPLICATE_TOKEN = process.env.REPLICATE_API_TOKEN || '';
const OPENROUTER_KEY = process.env.OPENROUTER_API_KEY || '';

// Models
const TTS_MODEL = 'minimax/speech-02-hd';
const VIDEO_MODEL = 'bytedance/seedance-1-lite';
const LIPSYNC_MODEL = 'devxpy/cog-wav2lip';

async function replicateAPI(method, path, body) {
  const res = await fetch(`https://api.replicate.com${path}`, {
    method,
    headers: {
      'Authorization': `Bearer ${REPLICATE_TOKEN}`,
      'Content-Type': 'application/json',
      'Prefer': 'wait=120',
    },
    body: body ? JSON.stringify(body) : undefined,
  });
  return res.json();
}

async function replicateAsync(method, path, body) {
  const res = await fetch(`https://api.replicate.com${path}`, {
    method,
    headers: {
      'Authorization': `Bearer ${REPLICATE_TOKEN}`,
      'Content-Type': 'application/json',
    },
    body: body ? JSON.stringify(body) : undefined,
  });
  return res.json();
}

async function pollPrediction(id, maxWait = 300000) {
  const start = Date.now();
  while (Date.now() - start < maxWait) {
    const pred = await replicateAsync('GET', `/v1/predictions/${id}`);
    if (pred.status === 'succeeded') return pred;
    if (pred.status === 'failed' || pred.status === 'canceled') {
      throw new Error(`Prediction ${id} ${pred.status}: ${pred.error || 'unknown'}`);
    }
    await new Promise(r => setTimeout(r, 5000));
  }
  throw new Error(`Prediction ${id} timed out`);
}

async function generateScript(productInfo, userNotes) {
  const prompt = `You are a viral short-form video scriptwriter. Write a 15-second sales script for a product ad.

Product info:
- Title: ${productInfo.title || 'Unknown'}
- Description: ${productInfo.description || 'N/A'}
- Domain: ${productInfo.domain || 'N/A'}
${userNotes ? `\nUser notes: ${userNotes}` : ''}

Requirements:
- 15 seconds max when spoken (about 40-50 words)
- Hook in first 2 seconds
- Highlight 1-2 key benefits
- End with clear CTA
- Conversational, energetic tone
- Written as spoken words only — NO stage directions, NO parenthetical notes like (music plays), NO sound effects

Script:`;

  const res = await fetch('https://openrouter.ai/api/v1/chat/completions', {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${OPENROUTER_KEY}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      model: 'google/gemini-2.0-flash-001',
      messages: [{ role: 'user', content: prompt }],
      max_tokens: 200,
    }),
  });
  const data = await res.json();
  return data.choices?.[0]?.message?.content?.trim() || 'Check out this amazing product!';
}

async function generateVideoPrompt(productInfo, script) {
  const prompt = `Generate a short prompt for an AI video model. The video should show a young professional person (mid-20s) looking at camera, speaking naturally with hand gestures, in a well-lit modern setting. They are presenting a product ad. Keep it to 1-2 sentences.

Product: ${productInfo.title || 'tech product'}
Script they're reading: "${script}"

Video prompt:`;

  const res = await fetch('https://openrouter.ai/api/v1/chat/completions', {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${OPENROUTER_KEY}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      model: 'google/gemini-2.0-flash-001',
      messages: [{ role: 'user', content: prompt }],
      max_tokens: 100,
    }),
  });
  const data = await res.json();
  return data.choices?.[0]?.message?.content?.trim() || 'A young professional person speaking to camera in a modern office, natural gestures, well-lit, 9:16 vertical';
}

// POST /api/ads/generate
router.post('/generate', async (req, res) => {
  try {
    const { url, notes, userId } = req.body;

    if (!url) {
      return res.status(400).json({ error: 'url is required' });
    }

    // Credit check
    const adCost = OPERATION_CREDITS['ad-maker'];
    if (userId) {
      const userCheck = await req.db.query('SELECT credits, is_subscribed FROM users WHERE external_id = $1', [userId]);
      const user = userCheck.rows[0];
      if (user && !user.is_subscribed) {
        if (user.credits < adCost) {
          return res.status(402).json({ error: 'Insufficient credits', credits: user.credits, cost: adCost });
        }
        await req.db.query('UPDATE users SET credits = credits - $1 WHERE external_id = $2', [adCost, userId]);
        console.log(`[AdMaker] Deducted ${adCost} credits from ${userId}`);
      }
    }

    const id = uuid();

    // Save initial record
    await req.db.query(
      `INSERT INTO ad_generations (id, user_id, product_url, notes, status, step, created_at)
       VALUES ($1, $2, $3, $4, 'processing', 'scraping', NOW())`,
      [id, userId || null, url, notes || null]
    );

    // Return immediately, process in background
    res.json({ success: true, id, status: 'processing', step: 'scraping' });

    // ===== Background pipeline =====
    (async () => {
      try {
        // Step 1: Scrape product page
        console.log(`[AdMaker] ${id} Step 1: Scraping ${url}`);
        const scrapeRes = await fetch(`http://127.0.0.1:3001/api/generate/preview`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ url }),
        });
        const scrapeData = await scrapeRes.json();
        const productInfo = scrapeData.preview || {};

        await req.db.query(
          `UPDATE ad_generations SET step = 'script', product_info = $1 WHERE id = $2`,
          [JSON.stringify(productInfo), id]
        );

        // Step 2: Generate sales script
        console.log(`[AdMaker] ${id} Step 2: Generating script`);
        const script = await generateScript(productInfo, notes);
        console.log(`[AdMaker] ${id} Script: "${script.substring(0, 80)}..."`);

        await req.db.query(
          `UPDATE ad_generations SET step = 'tts', script = $1 WHERE id = $2`,
          [script, id]
        );

        // Step 3: TTS voiceover
        console.log(`[AdMaker] ${id} Step 3: Generating voiceover`);
        const ttsPred = await replicateAsync('POST', `/v1/models/${TTS_MODEL}/predictions`, {
          input: {
            text: script,
            voice_id: 'Wise_Woman',
            speed: 1.1,
            emotion: 'happy',
          },
        });

        if (ttsPred.error) throw new Error(`TTS error: ${ttsPred.error}`);
        const ttsResult = await pollPrediction(ttsPred.id, 60000);
        const audioUrl = ttsResult.output;
        console.log(`[AdMaker] ${id} TTS done: ${audioUrl}`);

        await req.db.query(
          `UPDATE ad_generations SET step = 'video', audio_url = $1 WHERE id = $2`,
          [audioUrl, id]
        );

        // Step 4: Generate AI person video
        console.log(`[AdMaker] ${id} Step 4: Generating video`);
        const videoPrompt = await generateVideoPrompt(productInfo, script);
        console.log(`[AdMaker] ${id} Video prompt: "${videoPrompt.substring(0, 80)}..."`);

        const videoPred = await replicateAsync('POST', `/v1/models/${VIDEO_MODEL}/predictions`, {
          input: {
            prompt: videoPrompt,
            duration: 5,
            aspect_ratio: '9:16',
          },
        });

        console.log(`[AdMaker] ${id} Video prediction response:`, JSON.stringify(videoPred).substring(0, 200));
        if (!videoPred.id) throw new Error(`Video API error: ${JSON.stringify(videoPred).substring(0, 200)}`);
        if (videoPred.error || videoPred.detail) throw new Error(`Video error: ${videoPred.error || videoPred.detail}`);
        const videoResult = await pollPrediction(videoPred.id, 300000);
        const videoUrl = videoResult.output;
        console.log(`[AdMaker] ${id} Video done: ${videoUrl}`);

        await req.db.query(
          `UPDATE ad_generations SET step = 'lipsync', video_url = $1 WHERE id = $2`,
          [videoUrl, id]
        );

        // Step 5: Lip-sync audio onto video
        console.log(`[AdMaker] ${id} Step 5: Lip-syncing`);
        const lipsyncPred = await replicateAsync('POST', `/v1/models/${LIPSYNC_MODEL}/predictions`, {
          input: {
            face: videoUrl,
            audio: audioUrl,
            smooth: true,
          },
        });

        if (lipsyncPred.error) throw new Error(`Lipsync error: ${lipsyncPred.error}`);
        const lipsyncResult = await pollPrediction(lipsyncPred.id, 120000);
        const finalUrl = lipsyncResult.output;
        console.log(`[AdMaker] ${id} ✅ Done: ${finalUrl}`);

        await req.db.query(
          `UPDATE ad_generations SET status = 'succeeded', step = 'done', output_url = $1, completed_at = NOW() WHERE id = $2`,
          [finalUrl, id]
        );
      } catch (err) {
        console.error(`[AdMaker] ${id} FAILED at step:`, err.message);
        await req.db.query(
          `UPDATE ad_generations SET status = 'failed', error = $1, completed_at = NOW() WHERE id = $2`,
          [err.message, id]
        );
      }
    })();
  } catch (err) {
    console.error('[AdMaker] Error:', err.message);
    res.status(500).json({ error: err.message });
  }
});

// GET /api/ads/status/:id
router.get('/status/:id', async (req, res) => {
  try {
    const result = await req.db.query('SELECT * FROM ad_generations WHERE id = $1', [req.params.id]);
    if (!result.rows.length) return res.status(404).json({ error: 'Not found' });

    const gen = result.rows[0];
    res.json({
      id: gen.id,
      status: gen.status,
      step: gen.step,
      script: gen.script,
      audioUrl: gen.audio_url,
      videoUrl: gen.video_url,
      outputUrl: gen.output_url,
      error: gen.error,
      productInfo: gen.product_info ? JSON.parse(gen.product_info) : null,
      createdAt: gen.created_at,
      completedAt: gen.completed_at,
    });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

module.exports = router;
