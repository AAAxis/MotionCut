const express = require('express');
const router = express.Router();
const path = require('path');
const fs = require('fs');
const { generateReel } = require('../services/reelGenerator');

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
      downloadUrl: `/api/reels/download/${path.basename(result.file)}`
    });
  } catch (err) {
    console.error('[Reels] Error:', err.message);
    res.status(500).json({ error: err.message });
  }
});

// GET /api/reels/download/:filename
router.get('/download/:filename', (req, res) => {
  const file = path.join(__dirname, '..', 'output', req.params.filename);
  if (!fs.existsSync(file)) return res.status(404).json({ error: 'not found' });
  res.download(file);
});

module.exports = router;
