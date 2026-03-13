/**
 * /api/influencer — AI Influencer Video Generation
 *
 * POST /api/influencer/generate  → Generate AI influencer video (LivePortrait via Replicate)
 * GET  /api/influencer/status/:id → Check generation status
 * GET  /api/influencer/download/:filename → Download result
 */
const express = require('express');
const router = express.Router();
const https = require('https');
const fs = require('fs');
const path = require('path');
const { v4: uuid } = require('uuid');

const REPLICATE_TOKEN = process.env.REPLICATE_API_TOKEN || '';
const REPLICATE_MODEL = 'fofr/live-portrait';

// Preset avatars — must match avatars route
const AVATAR_IMAGES = {
  'avatar-1': '/avatars/sofia.jpg',   // Alex in app
  'avatar-2': '/avatars/marcus.jpg',  // Jordan in app
  'avatar-3': '/avatars/yuki.jpg',    // Sam in app
  'avatar-4': '/avatars/james.jpg',   // Riley in app
  'avatar-5': '/avatars/aria.jpg',
};

function replicateRequest(method, path, body) {
  return new Promise((resolve, reject) => {
    const opts = {
      hostname: 'api.replicate.com',
      path,
      method,
      headers: {
        Authorization: `Bearer ${REPLICATE_TOKEN}`,
        'Content-Type': 'application/json',
        // No Prefer:wait — use async polling instead
      },
    };
    const req = https.request(opts, (res) => {
      let d = '';
      res.on('data', (c) => (d += c));
      res.on('end', () => {
        try { resolve(JSON.parse(d)); }
        catch (e) { reject(new Error(`Replicate parse error: ${d.substring(0, 200)}`)); }
      });
    });
    req.on('error', reject);
    if (body) req.write(JSON.stringify(body));
    req.end();
  });
}

// POST /api/influencer/generate
router.post('/generate', async (req, res) => {
  try {
    const { avatarId, avatarUrl, referenceVideoUrl, topic, duration = 10, userId } = req.body;

    if (!referenceVideoUrl) {
      return res.status(400).json({ error: 'referenceVideoUrl is required' });
    }

    // Resolve avatar image URL
    let faceImageUrl = avatarUrl;
    if (!faceImageUrl && avatarId) {
      // Check preset
      const localPath = AVATAR_IMAGES[avatarId];
      if (localPath) {
        const serverBase = `${req.protocol}://${req.get('host')}`;
        faceImageUrl = `${serverBase}${localPath}`;
      } else {
        // Check DB for custom avatar
        const result = await req.db.query('SELECT thumbnail_url FROM avatars WHERE id = $1', [avatarId]);
        if (result.rows.length) faceImageUrl = result.rows[0].thumbnail_url;
      }
    }

    if (!faceImageUrl) {
      return res.status(400).json({ error: 'Could not resolve avatar image. Provide avatarId or avatarUrl.' });
    }

    console.log(`[Influencer] Generating: avatar=${avatarId || 'custom'}, video=${referenceVideoUrl}, duration=${duration}s`);

    // Create prediction on Replicate
    const prediction = await replicateRequest('POST', '/v1/predictions', {
      version: '067dd98cc3e5cb396c4a81d5489eab1b697af27aa308d4bd1e0a58e71e0e8cd5',
      input: {
        face_image: faceImageUrl,
        driving_video: referenceVideoUrl,
        live_portrait_dsize: 512,
        live_portrait_stitching: true,
        video_select_every_n_frames: 1,
      },
    });

    if (prediction.error || prediction.detail) {
      console.error('[Influencer] Replicate error:', prediction.error || prediction.detail);
      return res.status(500).json({ error: prediction.error || prediction.detail });
    }

    // Save to DB
    const id = uuid();
    await req.db.query(
      `INSERT INTO influencer_generations (id, user_id, avatar_id, reference_video_url, topic, duration, replicate_id, status, created_at)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8, NOW())`,
      [id, userId || null, avatarId || null, referenceVideoUrl, topic || null, duration, prediction.id, prediction.status || 'starting']
    );

    // Return immediately — client polls /status/:id
    res.json({
      success: true,
      id,
      status: prediction.status || 'starting',
      replicateId: prediction.id,
      pollUrl: `/api/influencer/status/${id}`,
    });
  } catch (err) {
    console.error('[Influencer] Error:', err.message);
    res.status(500).json({ error: err.message });
  }
});

// GET /api/influencer/status/:id
router.get('/status/:id', async (req, res) => {
  try {
    const result = await req.db.query(
      'SELECT * FROM influencer_generations WHERE id = $1',
      [req.params.id]
    );
    if (!result.rows.length) return res.status(404).json({ error: 'Not found' });

    const gen = result.rows[0];

    // If still processing, check Replicate
    if (gen.status !== 'succeeded' && gen.status !== 'failed') {
      const prediction = await replicateRequest('GET', `/v1/predictions/${gen.replicate_id}`);

      if (prediction.status !== gen.status) {
        const update = { status: prediction.status };
        if (prediction.status === 'succeeded' && prediction.output) {
          update.output_url = prediction.output;
          await req.db.query(
            `UPDATE influencer_generations SET status = $1, output_url = $2, completed_at = NOW() WHERE id = $3`,
            [update.status, update.output_url, gen.id]
          );
        } else {
          await req.db.query(
            `UPDATE influencer_generations SET status = $1 WHERE id = $2`,
            [update.status, gen.id]
          );
        }
        gen.status = update.status;
        gen.output_url = update.output_url || gen.output_url;
      }
    }

    res.json({
      id: gen.id,
      status: gen.status,
      outputUrl: gen.output_url,
      avatarId: gen.avatar_id,
      topic: gen.topic,
      duration: gen.duration,
      createdAt: gen.created_at,
      completedAt: gen.completed_at,
    });
  } catch (err) {
    console.error('[Influencer] Status error:', err.message);
    res.status(500).json({ error: err.message });
  }
});

// GET /api/influencer/history
router.get('/history', async (req, res) => {
  try {
    const userId = req.query.userId;
    const limit = Math.min(parseInt(req.query.limit) || 20, 50);
    const result = await req.db.query(
      `SELECT id, avatar_id, topic, duration, status, output_url, created_at, completed_at 
       FROM influencer_generations 
       ${userId ? 'WHERE user_id = $1' : ''} 
       ORDER BY created_at DESC LIMIT ${limit}`,
      userId ? [userId] : []
    );
    res.json({ generations: result.rows });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

module.exports = router;
