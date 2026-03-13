/**
 * /api/create — Unified AI Video Generation
 *
 * Two modes:
 *   1. Text-to-Video: User selects an AI model (Kling, Seedance) + types prompt → Replicate generates video
 *   2. Image-to-Video: User uploads their photo + types prompt → Replicate animates their face
 *
 * POST /api/create/generate   → Start generation
 * GET  /api/create/status/:id → Poll status
 */
const express = require('express');
const router = express.Router();
const { v4: uuid } = require('uuid');

const REPLICATE_TOKEN = process.env.REPLICATE_API_TOKEN || '';

// Default image-to-video model when user uploads photo
const DEFAULT_I2V_MODEL = 'kwaivgi/kling-v2.1';

// Known model configs — map model id to Replicate input format
const MODEL_CONFIGS = {
  'kwaivgi/kling-v2.1': {
    type: 'both', // supports text-to-video and image-to-video
    t2v_input: (prompt, duration) => ({ prompt, duration: duration <= 5 ? '5' : '10', aspect_ratio: '9:16' }),
    i2v_input: (prompt, imageUrl, duration) => ({ prompt, image: imageUrl, duration: duration <= 5 ? '5' : '10', aspect_ratio: '9:16' }),
  },
  'bytedance/seedance-1-lite': {
    type: 'both',
    t2v_input: (prompt, duration) => ({ prompt, duration, aspect_ratio: '9:16' }),
    i2v_input: (prompt, imageUrl, duration) => ({ prompt, image: imageUrl, duration, aspect_ratio: '9:16' }),
  },
  'bytedance/seedance-1-pro': {
    type: 'both',
    t2v_input: (prompt, duration) => ({ prompt, duration, aspect_ratio: '9:16' }),
    i2v_input: (prompt, imageUrl, duration) => ({ prompt, image: imageUrl, duration, aspect_ratio: '9:16' }),
  },
  'kwaivgi/kling-v1.6-standard': {
    type: 'both',
    t2v_input: (prompt, duration) => ({ prompt, duration: duration <= 5 ? '5' : '10', aspect_ratio: '9:16' }),
    i2v_input: (prompt, imageUrl, duration) => ({ prompt, start_image: imageUrl, duration: duration <= 5 ? '5' : '10', aspect_ratio: '9:16' }),
  },
};

async function replicateAPI(method, path, body) {
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

// POST /api/create/generate
router.post('/generate', async (req, res) => {
  try {
    const { modelId, prompt, imageUrl, duration = 5, userId } = req.body;

    if (!prompt) {
      return res.status(400).json({ error: 'prompt is required' });
    }

    const hasImage = !!imageUrl;
    const selectedModel = modelId || (hasImage ? DEFAULT_I2V_MODEL : 'kwaivgi/kling-v2.1');
    const config = MODEL_CONFIGS[selectedModel];

    let input;
    let mode;

    if (hasImage) {
      // Image-to-video: animate user's uploaded photo
      mode = 'image-to-video';
      if (config?.i2v_input) {
        input = config.i2v_input(prompt, imageUrl, duration);
      } else {
        // Generic fallback for unknown models
        input = { prompt, image: imageUrl, duration, aspect_ratio: '9:16' };
      }
    } else {
      // Text-to-video: generate from scratch
      mode = 'text-to-video';
      if (config?.t2v_input) {
        input = config.t2v_input(prompt, duration);
      } else {
        input = { prompt, duration, aspect_ratio: '9:16' };
      }
    }

    console.log(`[Create] ${mode}: model=${selectedModel}, prompt="${prompt.substring(0, 50)}...", hasImage=${hasImage}`);

    // Create prediction using model name (Replicate resolves to latest version)
    const prediction = await replicateAPI('POST', '/v1/models/' + selectedModel + '/predictions', {
      input,
    });

    if (prediction.error || prediction.detail) {
      console.error('[Create] Replicate error:', prediction.error || prediction.detail);
      return res.status(500).json({ error: prediction.error || prediction.detail || 'Replicate API error' });
    }

    // Save to DB
    const id = uuid();
    await req.db.query(
      `INSERT INTO ai_generations (id, user_id, model_id, mode, prompt, image_url, duration, replicate_id, status, created_at)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, NOW())`,
      [id, userId || null, selectedModel, mode, prompt, imageUrl || null, duration, prediction.id, prediction.status || 'starting']
    );

    res.json({
      success: true,
      id,
      mode,
      model: selectedModel,
      status: prediction.status || 'starting',
      replicateId: prediction.id,
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
          // Output can be string or array
          outputUrl = Array.isArray(prediction.output) ? prediction.output[0] : prediction.output;
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

module.exports = router;
