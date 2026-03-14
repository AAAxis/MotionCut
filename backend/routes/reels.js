const express = require('express');
const router = express.Router();
const path = require('path');
const fs = require('fs');
const https = require('https');
const { v4: uuid } = require('uuid');
const { execSync } = require('child_process');
const os = require('os');
const { generateReel } = require('../services/reelGenerator');

const REPLICATE_TOKEN = process.env.REPLICATE_API_TOKEN || '';

const AVATAR_IMAGES = {
  'avatar-1': '/avatars/sofia.jpg',
  'avatar-2': '/avatars/marcus.jpg',
  'avatar-3': '/avatars/yuki.jpg',
  'avatar-4': '/avatars/james.jpg',
  'avatar-5': '/avatars/aria.jpg',
};

// ===== Audio helpers =====
async function downloadFile(url, filepath) {
  const res = await fetch(url);
  fs.writeFileSync(filepath, Buffer.from(await res.arrayBuffer()));
}

function extractAudio(videoPath, audioPath) {
  try {
    execSync(`ffprobe -v error -select_streams a -show_entries stream=codec_type -of csv=p=0 "${videoPath}" 2>/dev/null`);
    execSync(`ffmpeg -y -i "${videoPath}" -vn -acodec aac -b:a 128k "${audioPath}" 2>/dev/null`);
    return fs.existsSync(audioPath);
  } catch (e) {
    return false; // no audio track
  }
}

function mergeVideoWithAudio(videoPath, audioPath, outputPath) {
  execSync(`ffmpeg -y -i "${videoPath}" -i "${audioPath}" -c:v copy -c:a aac -map 0:v:0 -map 1:a:0 -shortest -movflags +faststart "${outputPath}" 2>/dev/null`);
}

function replicateRequest(method, requestPath, body) {
  return new Promise((resolve, reject) => {
    const opts = {
      hostname: 'api.replicate.com',
      path: requestPath,
      method,
      headers: {
        Authorization: `Bearer ${REPLICATE_TOKEN}`,
        'Content-Type': 'application/json',
      },
    };

    const req = https.request(opts, (res) => {
      let data = '';
      res.on('data', (chunk) => (data += chunk));
      res.on('end', () => {
        try {
          resolve(JSON.parse(data));
        } catch {
          reject(new Error(`Replicate parse error: ${data.substring(0, 200)}`));
        }
      });
    });

    req.on('error', reject);
    if (body) req.write(JSON.stringify(body));
    req.end();
  });
}

async function resolveAvatarImageURL(req, avatarId, avatarUrl) {
  if (avatarUrl) return avatarUrl;
  if (!avatarId) return null;

  const presetPath = AVATAR_IMAGES[avatarId];
  if (presetPath) {
    return `${req.protocol}://${req.get('host')}${presetPath}`;
  }

  const uploadResult = await req.db.query(
    'SELECT file_url FROM avatar_uploads WHERE id = $1 LIMIT 1',
    [avatarId]
  );
  if (uploadResult.rows.length) {
    return `${req.protocol}://${req.get('host')}${uploadResult.rows[0].file_url}`;
  }

  const avatarResult = await req.db.query(
    'SELECT thumbnail_url, source_image_url FROM avatars WHERE id = $1 LIMIT 1',
    [avatarId]
  );
  if (avatarResult.rows.length) {
    return avatarResult.rows[0].thumbnail_url || avatarResult.rows[0].source_image_url;
  }

  return null;
}

// POST /api/reels/generate
router.post('/generate', async (req, res) => {
  try {
    const { topic, language = 'en', duration = 10 } = req.body;
    if (!topic) return res.status(400).json({ error: 'topic is required' });

    const result = await generateReel({ topic, language, duration: Math.min(duration, 15) });

    res.json({
      success: true,
      hook: result.hook,
      subtitle: result.subtitle,
      search: result.search,
      duration: result.duration,
      downloadUrl: `/api/reels/download/${path.basename(result.file)}`,
    });
  } catch (err) {
    console.error('[Reels/generate] Error:', err.message);
    res.status(500).json({ error: err.message });
  }
});

// POST /api/reels/influence
router.post('/influence', async (req, res) => {
  try {
    const {
      topic,
      duration = 10,
      userId,
      influencerId,
      avatarId,
      avatarUrl,
      referenceVideoUrl,
    } = req.body;

    if (!referenceVideoUrl) {
      return res.status(400).json({ error: 'referenceVideoUrl is required' });
    }

    const resolvedAvatarId = avatarId || influencerId;
    const faceImageUrl = await resolveAvatarImageURL(req, resolvedAvatarId, avatarUrl);
    if (!faceImageUrl) {
      return res.status(400).json({ error: 'Could not resolve avatar image.' });
    }

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
      return res.status(500).json({ error: prediction.error || prediction.detail });
    }

    const id = uuid();
    await req.db.query(
      `INSERT INTO influencer_generations
        (id, user_id, avatar_id, reference_video_url, topic, duration, replicate_id, status, created_at)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8, NOW())`,
      [
        id,
        userId || null,
        resolvedAvatarId || null,
        referenceVideoUrl,
        topic || null,
        Math.min(duration, 15),
        prediction.id,
        prediction.status || 'starting',
      ]
    );

    // Extract audio from reference video in background (for later merge)
    (async () => {
      try {
        const tmpDir = path.join(os.tmpdir(), `reel-${id}`);
        fs.mkdirSync(tmpDir, { recursive: true });
        const refPath = path.join(tmpDir, 'reference.mp4');
        const audioPath = path.join(tmpDir, 'original_audio.aac');
        await downloadFile(referenceVideoUrl, refPath);
        const hasAudio = extractAudio(refPath, audioPath);
        if (hasAudio) {
          // Copy audio to persistent location
          const persistAudio = `/tmp/reel-audio-${id}.aac`;
          fs.copyFileSync(audioPath, persistAudio);
          console.log(`[Reel] ${id} Original audio extracted: ${persistAudio}`);
        } else {
          console.log(`[Reel] ${id} Reference video has no audio track`);
        }
        try { fs.rmSync(tmpDir, { recursive: true }); } catch(e) {}
      } catch (err) {
        console.error(`[Reel] ${id} Audio extraction failed:`, err.message);
      }
    })();

    res.json({
      success: true,
      id,
      status: prediction.status || 'starting',
      pollUrl: `/api/reels/influence/status/${id}`,
    });
  } catch (err) {
    console.error('[Reels/influence] Error:', err.message);
    res.status(500).json({ error: err.message });
  }
});

// GET /api/reels/influence/status/:id
router.get('/influence/status/:id', async (req, res) => {
  try {
    const result = await req.db.query(
      'SELECT * FROM influencer_generations WHERE id = $1',
      [req.params.id]
    );
    if (!result.rows.length) return res.status(404).json({ error: 'Not found' });

    const generation = result.rows[0];
    let status = generation.status;
    let outputUrl = generation.output_url;

    if (status !== 'succeeded' && status !== 'failed') {
      const prediction = await replicateRequest('GET', `/v1/predictions/${generation.replicate_id}`);
      status = prediction.status || status;

      if (status === 'succeeded' && prediction.output) {
        outputUrl = Array.isArray(prediction.output) ? prediction.output[0] : prediction.output;
        
        // Merge original audio if available
        const audioFile = `/tmp/reel-audio-${generation.id}.aac`;
        if (fs.existsSync(audioFile)) {
          try {
            const tmpDir = path.join(os.tmpdir(), `reel-merge-${generation.id}`);
            fs.mkdirSync(tmpDir, { recursive: true });
            const videoPath = path.join(tmpDir, 'generated.mp4');
            const mergedPath = path.join(tmpDir, 'final.mp4');
            await downloadFile(outputUrl, videoPath);
            mergeVideoWithAudio(videoPath, audioFile, mergedPath);
            
            // Save merged video and serve locally
            const publicPath = `/tmp/reel-${generation.id}-final.mp4`;
            fs.copyFileSync(mergedPath, publicPath);
            outputUrl = `/api/reels/influence/download/${generation.id}`;
            console.log(`[Reel] ${generation.id} Merged with original audio`);
            
            // Cleanup
            try { fs.rmSync(tmpDir, { recursive: true }); } catch(e) {}
            try { fs.unlinkSync(audioFile); } catch(e) {}
          } catch (mergeErr) {
            console.error(`[Reel] ${generation.id} Audio merge failed:`, mergeErr.message);
            // Keep original video URL without audio
          }
        }
        
        await req.db.query(
          `UPDATE influencer_generations
           SET status = $1, output_url = $2, completed_at = NOW()
           WHERE id = $3`,
          [status, outputUrl, generation.id]
        );
      } else if (status !== generation.status) {
        await req.db.query(
          'UPDATE influencer_generations SET status = $1 WHERE id = $2',
          [status, generation.id]
        );
      }
    }

    res.json({
      id: generation.id,
      status,
      outputUrl,
      topic: generation.topic,
      duration: generation.duration,
      createdAt: generation.created_at,
      completedAt: generation.completed_at,
    });
  } catch (err) {
    console.error('[Reels/influence/status] Error:', err.message);
    res.status(500).json({ error: err.message });
  }
});

// GET /api/reels/influence/download/:id — serve merged reel with original audio
router.get('/influence/download/:id', (req, res) => {
  const filepath = `/tmp/reel-${req.params.id}-final.mp4`;
  if (fs.existsSync(filepath)) {
    res.setHeader('Content-Type', 'video/mp4');
    res.sendFile(filepath);
  } else {
    res.status(404).json({ error: 'Video not found or expired' });
  }
});

// GET /api/reels/download/:filename
router.get('/download/:filename', (req, res) => {
  const file = path.join(__dirname, '..', 'output', req.params.filename);
  if (!fs.existsSync(file)) return res.status(404).json({ error: 'not found' });
  res.download(file);
});

module.exports = router;
