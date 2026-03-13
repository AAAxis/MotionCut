const express = require('express');
const router = express.Router();

const REPLICATE_TOKEN = process.env.REPLICATE_API_TOKEN;
const BASE = 'https://api.replicate.com/v1';

const COLLECTIONS = [
  'text-to-video',
  'image-to-video', 
  'text-to-image',
  'face-swap',
  'lipsync',
  'ai-face-generator',
];

async function fetchCollection(slug) {
  const res = await fetch(`${BASE}/collections/${slug}`, {
    headers: { 'Authorization': `Bearer ${REPLICATE_TOKEN}` },
  });
  if (!res.ok) return [];
  const data = await res.json();
  return (data.models || []).map(m => ({
    id: `${m.owner}/${m.name}`,
    name: m.name,
    owner: m.owner,
    description: m.description || '',
    cover_image: m.cover_image_url || m.featured_image_url || null,
    collection: slug,
    url: m.url || `https://replicate.com/${m.owner}/${m.name}`,
    run_count: m.run_count || 0,
  }));
}

// GET /api/models — list all AI models from Replicate collections
router.get('/', async (req, res) => {
  try {
    const collection = req.query.collection; // optional filter
    const slugs = collection ? [collection] : COLLECTIONS;
    
    const results = await Promise.all(slugs.map(fetchCollection));
    const models = results.flat();
    
    // Sort by popularity
    models.sort((a, b) => (b.run_count || 0) - (a.run_count || 0));
    
    res.json({ models, total: models.length });
  } catch (err) {
    console.error('Models fetch error:', err.message);
    res.status(500).json({ error: 'Failed to fetch models' });
  }
});

// GET /api/models/collections — list available collections
router.get('/collections', async (req, res) => {
  try {
    const r = await fetch(`${BASE}/collections`, {
      headers: { 'Authorization': `Bearer ${REPLICATE_TOKEN}` },
    });
    const data = await r.json();
    const collections = (data.results || []).map(c => ({
      slug: c.slug,
      name: c.name,
      description: c.description || '',
    }));
    res.json({ collections });
  } catch (err) {
    res.status(500).json({ error: 'Failed to fetch collections' });
  }
});

// GET /api/models/:owner/:name — get single model details
router.get('/:owner/:name', async (req, res) => {
  try {
    const { owner, name } = req.params;
    const r = await fetch(`${BASE}/models/${owner}/${name}`, {
      headers: { 'Authorization': `Bearer ${REPLICATE_TOKEN}` },
    });
    if (!r.ok) return res.status(404).json({ error: 'Model not found' });
    
    const m = await r.json();
    
    // Get latest version's schema for input params
    const schema = m.latest_version?.openapi_schema?.components?.schemas?.Input?.properties || {};
    const inputs = Object.entries(schema).map(([key, val]) => ({
      name: key,
      type: val.type || 'string',
      description: val.description || '',
      default: val.default,
      enum: val.enum || null,
    }));

    res.json({
      id: `${m.owner}/${m.name}`,
      name: m.name,
      owner: m.owner,
      description: m.description || '',
      cover_image: m.cover_image_url || null,
      url: m.url,
      run_count: m.run_count || 0,
      latest_version: m.latest_version?.id || null,
      inputs,
    });
  } catch (err) {
    res.status(500).json({ error: 'Failed to fetch model details' });
  }
});

module.exports = router;
