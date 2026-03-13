/**
 * /api/generate — Main video generation endpoint
 *
 * POST /api/generate
 *   { url, prompt, options: { scenes, duration, style } }
 *   → Returns { generationId, status: 'processing' }
 *
 * GET /api/generate/:id
 *   → Returns generation status + result
 */
const express = require('express');
const router = express.Router();
const { v4: uuid } = require('uuid');
const { scrapeUrl } = require('../services/scraper');
const { generateScript } = require('../services/scriptGenerator');
const { fetchFootageForScenes } = require('../services/stockFootage');
const { renderVideo } = require('../services/videoRenderer');
const { listVoices, VOICES } = require('../services/voiceover');

// POST /api/generate — Start a new video generation
router.post('/', async (req, res) => {
  const { url, prompt, userId, options = {} } = req.body;
  if (!options.duration) options.duration = 30; // Default to 30s if not specified

  if (!url) {
    return res.status(400).json({ error: 'URL is required' });
  }

  // Check credits
  if (userId) {
    const creditCheck = await req.db.query(
      'SELECT credits, is_subscribed FROM users WHERE external_id = $1',
      [userId]
    );
    const user = creditCheck.rows[0];
    if (user && !user.is_subscribed && user.credits <= 0) {
      return res.status(402).json({ error: 'No credits remaining', credits: 0 });
    }
  }

  // Create generation record
  const genId = uuid();
  await req.db.query(
    `INSERT INTO generations (id, user_id, source_url, prompt, status)
     VALUES ($1, $2, $3, $4, 'processing')`,
    [genId, userId || null, url, prompt || '']
  );

  // Return immediately, process in background
  res.json({ generationId: genId, status: 'processing' });

  // Background processing
  processGeneration(genId, url, prompt, userId, options, req.db).catch(err => {
    console.error(`Generation ${genId} failed:`, err);
  });
});

// GET /api/generate/:id — Check generation status
router.get('/:id', async (req, res) => {
  const { id } = req.params;
  const result = await req.db.query(
    'SELECT * FROM generations WHERE id = $1',
    [id]
  );

  if (!result.rows[0]) {
    return res.status(404).json({ error: 'Generation not found' });
  }

  const gen = result.rows[0];
  res.json({
    id: gen.id,
    status: gen.status,
    resultVideoUrl: gen.result_video_url,
    thumbnailUrl: gen.thumbnail_url,
    script: gen.script,
    error: gen.error,
    createdAt: gen.created_at,
  });
});

// POST /api/generate/preview — Scrape URL and return preview (no video generation)
router.post('/preview', async (req, res) => {
  const { url } = req.body;
  if (!url) return res.status(400).json({ error: 'URL is required' });

  try {
    const scraped = await scrapeUrl(url);
    res.json({ preview: scraped });
  } catch (err) {
    res.status(500).json({ error: 'Failed to scrape URL', message: err.message });
  }
});

// POST /api/generate/script — Generate script only (for preview/editing)
router.post('/script', async (req, res) => {
  const { url, prompt, options = {} } = req.body;
  if (!url) return res.status(400).json({ error: 'URL is required' });

  try {
    const scraped = await scrapeUrl(url);
    const script = await generateScript(scraped, prompt, options);
    res.json({ script, scraped });
  } catch (err) {
    res.status(500).json({ error: 'Failed to generate script', message: err.message });
  }
});

// GET /api/generate/voices — List available voices
router.get('/voices', async (req, res) => {
  try {
    const voices = await listVoices();
    res.json({ voices, defaults: VOICES });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

/**
 * Background: full generation pipeline
 */
async function processGeneration(genId, url, prompt, userId, options, db) {
  try {
    // 1. Scrape
    console.log(`[${genId}] Scraping ${url}...`);
    const scraped = await scrapeUrl(url);

    // 2. Generate script
    console.log(`[${genId}] Generating script...`);
    const script = await generateScript(scraped, prompt, options);

    await db.query(
      'UPDATE generations SET script = $1 WHERE id = $2',
      [JSON.stringify(script), genId]
    );

    // 3. Fetch stock footage for each scene
    console.log(`[${genId}] Fetching stock footage...`);
    const scenesWithFootage = await fetchFootageForScenes(script.scenes);

    // 4. Render video
    console.log(`[${genId}] Rendering video...`);
    const result = await renderVideo(scenesWithFootage, genId, { voiceId: options.voiceId });

    const videoUrl = `${process.env.BASE_URL || 'http://localhost:3001'}${result.url}`;

    // 5. Update DB
    await db.query(
      `UPDATE generations SET status = 'completed', result_video_url = $1, updated_at = NOW() WHERE id = $2`,
      [videoUrl, genId]
    );

    // 6. Deduct credit
    if (userId) {
      await db.query(
        'UPDATE users SET credits = GREATEST(credits - 1, 0) WHERE external_id = $1 AND is_subscribed = false',
        [userId]
      );
    }

    console.log(`[${genId}] ✅ Done: ${videoUrl}`);
  } catch (err) {
    console.error(`[${genId}] ❌ Error:`, err);
    await db.query(
      `UPDATE generations SET status = 'failed', error = $1, updated_at = NOW() WHERE id = $2`,
      [err.message, genId]
    );
  }
}

module.exports = router;
