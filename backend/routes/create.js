/**
 * /api/create — Unified AI Video Generation
 *
 * Two modes:
 *   1. Text-to-Video: User selects an AI model + types prompt → Replicate generates video
 *   2. Image-to-Video: User uploads their photo + types prompt → Replicate animates their face
 *
 * POST /api/create/generate   → Start generation
 * GET  /api/create/status/:id → Poll status
 */
const express = require('express');
const router = express.Router();
const { v4: uuid } = require('uuid');
const { fal } = require('@fal-ai/client');
const { execSync } = require('child_process');
const fs = require('fs');
const path = require('path');
const os = require('os');

const { calculateCost } = require('../config/credits');
const { checkRateLimit, recordGeneration } = require('../middleware/rateLimit');
const REPLICATE_TOKEN = process.env.REPLICATE_API_TOKEN || '';
const FAL_KEY = process.env.FAL_KEY || '';

// Configure fal.ai as fallback
if (FAL_KEY) fal.config({ credentials: FAL_KEY });

const FAL_VIDEO_MODEL = 'fal-ai/pixverse/v4/text-to-video';

// Model configs — input format per model
const MODEL_CONFIGS = {
  // Seedance Lite: text-to-video AND image-to-video, image is optional
  'bytedance/seedance-1-lite': {
    t2v: (prompt, duration) => ({ prompt, duration: duration || 5, aspect_ratio: '9:16' }),
    i2v: (prompt, imageUrl, duration) => ({ prompt, image: imageUrl, duration: duration || 5, aspect_ratio: '9:16' }),
  },
  // Seedance Pro: same as lite but higher quality
  'bytedance/seedance-1-pro': {
    t2v: (prompt, duration) => ({ prompt, duration: duration || 5, aspect_ratio: '9:16' }),
    i2v: (prompt, imageUrl, duration) => ({ prompt, image: imageUrl, duration: duration || 5, aspect_ratio: '9:16' }),
  },
  // MiniMax: text-to-video AND image-to-video
  'minimax/video-01': {
    t2v: (prompt) => ({ prompt, prompt_optimizer: true }),
    i2v: (prompt, imageUrl) => ({ prompt, first_frame_image: imageUrl, prompt_optimizer: true }),
  },
  // Kling v2.1: IMAGE-TO-VIDEO ONLY (requires start_image)
  'kwaivgi/kling-v2.1': {
    t2v: null, // not supported
    i2v: (prompt, imageUrl, duration) => ({ prompt, start_image: imageUrl, duration: duration <= 5 ? 5 : 10, mode: 'standard', aspect_ratio: '9:16' }),
  },
  // Kling v1.6: also i2v preferred
  'kwaivgi/kling-v1.6-standard': {
    t2v: null,
    i2v: (prompt, imageUrl, duration) => ({ prompt, start_image: imageUrl, duration: duration <= 5 ? 5 : 10, aspect_ratio: '9:16' }),
  },
};

const DEFAULT_T2V = 'bytedance/seedance-1-lite';
const DEFAULT_I2V = 'kwaivgi/kling-v2.1';

async function replicateAPI(method, path, body) {
  const res = await fetch(`https://api.replicate.com${path}`, {
    method,
    headers: {
      'Authorization': `Bearer ${REPLICATE_TOKEN}`,
      'Content-Type': 'application/json',
    },
    body: body ? JSON.stringify(body) : undefined,
  });
  const data = await res.json();
  data._httpStatus = res.status;
  return data;
}

// POST /api/create/generate
// ===== Audio helpers =====
async function downloadFile(url, filepath) {
  const res = await fetch(url);
  fs.writeFileSync(filepath, Buffer.from(await res.arrayBuffer()));
}

function extractAudioFromVideo(videoPath, audioPath) {
  try {
    execSync(`ffprobe -v error -select_streams a -show_entries stream=codec_type -of csv=p=0 "${videoPath}" 2>/dev/null`);
    execSync(`ffmpeg -y -i "${videoPath}" -vn -acodec aac -b:a 128k "${audioPath}" 2>/dev/null`);
    return fs.existsSync(audioPath);
  } catch (e) { return false; }
}

function mergeVideoAudio(videoPath, audioPath, outputPath) {
  execSync(`ffmpeg -y -i "${videoPath}" -i "${audioPath}" -c:v copy -c:a aac -map 0:v:0 -map 1:a:0 -shortest -movflags +faststart "${outputPath}" 2>/dev/null`);
}

router.post('/generate', async (req, res) => {
  try {
    let { modelId, prompt, imageUrl, duration = 5, userId, referenceVideoUrl } = req.body;

    if (!prompt) {
      return res.status(400).json({ error: 'prompt is required' });
    }

    // Rate limit check
    if (userId) {
      const rateCheck = await checkRateLimit(req.db, userId);
      if (!rateCheck.allowed) {
        return res.status(429).json(rateCheck);
      }
    }

    // Credit check
    if (userId) {
      const userCheck = await req.db.query('SELECT credits, is_subscribed FROM users WHERE external_id = $1', [userId]);
      let user = userCheck.rows[0];
      if (!user) {
        // Auto-create user with free credits
        const insertResult = await req.db.query(
          'INSERT INTO users (external_id, credits) VALUES ($1, 10) ON CONFLICT (external_id) DO NOTHING RETURNING credits',
          [userId]
        );
        user = insertResult.rows[0] || { credits: 10, is_subscribed: false };
      }
      if (user && !user.is_subscribed) {
        const cost = calculateCost(modelId || 'bytedance/seedance-1-lite', duration);
        if (user.credits < cost) {
          return res.status(402).json({ error: 'Insufficient credits', credits: user.credits, cost });
        }
        // Deduct credits
        await req.db.query('UPDATE users SET credits = credits - $1 WHERE external_id = $2', [cost, userId]);
        console.log(`[Create] Deducted ${cost} credits from ${userId}`);
      }
    }

    const hasImage = !!imageUrl;
    
    // Pick model and build input
    let selectedModel = modelId;
    let input;
    let mode;

    if (hasImage) {
      mode = 'image-to-video';
      // If selected model doesn't support i2v, fall back
      if (!selectedModel || !MODEL_CONFIGS[selectedModel]?.i2v) {
        selectedModel = DEFAULT_I2V;
      }
      const config = MODEL_CONFIGS[selectedModel];
      input = config.i2v(prompt, imageUrl, duration);
    } else {
      mode = 'text-to-video';
      // If selected model doesn't support t2v, fall back
      if (!selectedModel || !MODEL_CONFIGS[selectedModel]?.t2v) {
        selectedModel = DEFAULT_T2V;
      }
      const config = MODEL_CONFIGS[selectedModel];
      input = config.t2v(prompt, duration);
    }

    console.log(`[Create] ${mode}: model=${selectedModel}, prompt="${prompt.substring(0, 60)}", hasImage=${hasImage}`);

    // Create prediction — try Replicate first, fal.ai as fallback on 429
    let prediction = await replicateAPI('POST', `/v1/models/${selectedModel}/predictions`, { input });

    let usedFal = false;
    const isRateLimited = prediction._httpStatus === 429 ||
      (prediction.detail && (prediction.detail.includes('throttled') || prediction.detail.includes('rate limit'))) ||
      (prediction.error && typeof prediction.error === 'string' && prediction.error.includes('throttled'));
    const isError = prediction._httpStatus >= 400 || prediction.error || prediction.detail;
    if (isRateLimited || (isError && mode === 'text-to-video')) {
      console.log(`[Create] Replicate ${isRateLimited ? 'rate-limited' : 'error'}, trying fal.ai fallback...`);
      if (FAL_KEY && mode === 'text-to-video') {
        try {
          const falResult = await fal.subscribe(FAL_VIDEO_MODEL, {
            input: { prompt, duration: String(duration || 5), aspect_ratio: '9:16', quality: 'high' },
            logs: false, pollInterval: 5000,
          });
          const videoUrl = falResult.data?.video?.url;
          if (videoUrl) {
            usedFal = true;
            prediction = { id: `fal-${uuid().substring(0,8)}`, status: 'succeeded', output: videoUrl };
            console.log(`[Create] fal.ai fallback succeeded: ${videoUrl.substring(0, 60)}`);
          }
        } catch (falErr) {
          console.error('[Create] fal.ai fallback failed:', falErr.message);
        }
      }
      if (!usedFal) {
        return res.status(429).json({ error: 'Rate limited. Please try again in a minute.' });
      }
    }

    if (!usedFal && (prediction.error || prediction.detail)) {
      console.error('[Create] Replicate error:', prediction.error || prediction.detail);
      return res.status(500).json({ error: prediction.error || prediction.detail || 'Replicate API error' });
    }

    console.log(`[Create] ${usedFal ? 'fal.ai' : 'Replicate'} prediction: ${prediction.id}, status=${prediction.status}`);

    // Save to DB
    const id = uuid();
    const finalModel = usedFal ? FAL_VIDEO_MODEL : selectedModel;
    const outputUrl = usedFal ? prediction.output : null;
    await req.db.query(
      `INSERT INTO ai_generations (id, user_id, model_id, mode, prompt, image_url, duration, replicate_id, status, output_url, created_at${usedFal ? ', completed_at' : ''})
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, NOW()${usedFal ? ', NOW()' : ''})`,
      [id, userId || null, finalModel, mode, prompt, imageUrl || null, duration, prediction.id, prediction.status || 'starting', outputUrl]
    );

    // Extract audio from reference video in background (for later merge)
    if (referenceVideoUrl) {
      (async () => {
        try {
          const tmpDir = path.join(os.tmpdir(), `create-audio-${id}`);
          fs.mkdirSync(tmpDir, { recursive: true });
          const refPath = path.join(tmpDir, 'ref.mp4');
          await downloadFile(referenceVideoUrl, refPath);
          const audioPath = `/tmp/create-audio-${id}.aac`;
          const hasAudio = extractAudioFromVideo(refPath, audioPath);
          console.log(`[Create] ${id} Reference audio: ${hasAudio ? 'extracted' : 'no audio track'}`);
          try { fs.rmSync(tmpDir, { recursive: true }); } catch(e) {}
        } catch (err) {
          console.error(`[Create] ${id} Audio extraction failed:`, err.message);
        }
      })();
    }

    // Record generation for rate limiting
    await recordGeneration(req.db, userId);

    res.json({
      success: true,
      id,
      mode,
      model: finalModel,
      status: prediction.status || 'starting',
      replicateId: prediction.id,
      outputUrl,
    });
  } catch (err) {
    console.error('[Create] Error:', err.message);
    res.status(500).json({ error: err.message });
  }
});

// GET /api/create/status/:id
router.get('/status/:id', async (req, res) => {
  try {
    const result = await req.db.query('SELECT * FROM ai_generations WHERE id = $1', [req.params.id]);
    if (!result.rows.length) return res.status(404).json({ error: 'Not found' });

    const gen = result.rows[0];

    // Poll Replicate if still processing
    if (gen.status !== 'succeeded' && gen.status !== 'failed' && gen.status !== 'canceled') {
      const prediction = await replicateAPI('GET', `/v1/predictions/${gen.replicate_id}`);

      if (prediction.status !== gen.status) {
        let outputUrl = gen.output_url;
        if (prediction.status === 'succeeded' && prediction.output) {
          outputUrl = Array.isArray(prediction.output) ? prediction.output[0] : prediction.output;
          
          // Merge reference audio if available
          const audioFile = `/tmp/create-audio-${gen.id}.aac`;
          if (fs.existsSync(audioFile)) {
            try {
              const tmpDir = path.join(os.tmpdir(), `create-merge-${gen.id}`);
              fs.mkdirSync(tmpDir, { recursive: true });
              const videoPath = path.join(tmpDir, 'video.mp4');
              const mergedPath = path.join(tmpDir, 'merged.mp4');
              await downloadFile(outputUrl, videoPath);
              mergeVideoAudio(videoPath, audioFile, mergedPath);
              const publicPath = `/tmp/create-${gen.id}-final.mp4`;
              fs.copyFileSync(mergedPath, publicPath);
              outputUrl = `/api/create/download/${gen.id}`;
              console.log(`[Create] ${gen.id} Merged with reference audio`);
              try { fs.rmSync(tmpDir, { recursive: true }); } catch(e) {}
              try { fs.unlinkSync(audioFile); } catch(e) {}
            } catch (mergeErr) {
              console.error(`[Create] ${gen.id} Audio merge failed:`, mergeErr.message);
            }
          }
        }
        const errorMsg = prediction.status === 'failed' ? (prediction.error || 'Generation failed') : null;

        await req.db.query(
          `UPDATE ai_generations SET status = $1, output_url = $2, error = $3, completed_at = CASE WHEN $1 IN ('succeeded','failed') THEN NOW() ELSE completed_at END WHERE id = $4`,
          [prediction.status, outputUrl, errorMsg, gen.id]
        );
        gen.status = prediction.status;
        gen.output_url = outputUrl;
        gen.error = errorMsg;
      }
    }

    res.json({
      id: gen.id,
      status: gen.status,
      mode: gen.mode,
      model: gen.model_id,
      prompt: gen.prompt,
      outputUrl: gen.output_url,
      error: gen.error,
      duration: gen.duration,
      createdAt: gen.created_at,
      completedAt: gen.completed_at,
    });
  } catch (err) {
    console.error('[Create] Status error:', err.message);
    res.status(500).json({ error: err.message });
  }
});

// GET /api/create/history?userId=xxx
router.get('/history', async (req, res) => {
  try {
    const userId = req.query.userId;
    const limit = Math.min(parseInt(req.query.limit) || 20, 50);
    const result = await req.db.query(
      `SELECT id, model_id, mode, prompt, image_url, duration, status, output_url, error, created_at, completed_at
       FROM ai_generations ${userId ? 'WHERE user_id = $1' : ''} ORDER BY created_at DESC LIMIT ${limit}`,
      userId ? [userId] : []
    );
    res.json({ generations: result.rows });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// GET /api/create/download/:id — serve merged video with reference audio
router.get('/download/:id', (req, res) => {
  const filepath = `/tmp/create-${req.params.id}-final.mp4`;
  if (fs.existsSync(filepath)) {
    res.setHeader('Content-Type', 'video/mp4');
    res.sendFile(filepath);
  } else {
    res.status(404).json({ error: 'Video not found or expired' });
  }
});

module.exports = router;
