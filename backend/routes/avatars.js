/**
 * /api/avatars — AI Influencer Avatar management
 *
 * GET  /api/avatars           → List preset + custom avatars
 * GET  /api/avatars/:id       → Get single avatar
 * POST /api/avatars           → Create custom avatar
 * DELETE /api/avatars/:id     → Delete custom avatar
 */
const express = require('express');
const router = express.Router();
const { v4: uuid } = require('uuid');

// 5 preset avatars
const PRESET_AVATARS = [
  {
    id: 'avatar-1',
    name: 'Sofia',
    gender: 'female',
    style: 'professional',
    thumbnail: '/avatars/sofia.jpg',
    preset: true
  },
  {
    id: 'avatar-2',
    name: 'Marcus',
    gender: 'male',
    style: 'casual',
    thumbnail: '/avatars/marcus.jpg',
    preset: true
  },
  {
    id: 'avatar-3',
    name: 'Yuki',
    gender: 'female',
    style: 'creative',
    thumbnail: '/avatars/yuki.jpg',
    preset: true
  },
  {
    id: 'avatar-4',
    name: 'James',
    gender: 'male',
    style: 'business',
    thumbnail: '/avatars/james.jpg',
    preset: true
  },
  {
    id: 'avatar-5',
    name: 'Aria',
    gender: 'female',
    style: 'lifestyle',
    thumbnail: '/avatars/aria.jpg',
    preset: true
  }
];

// GET /api/avatars — list all avatars (presets + user's custom)
router.get('/', async (req, res) => {
  try {
    const userId = req.query.userId;
    let custom = [];

    if (userId) {
      const result = await req.db.query(
        'SELECT * FROM avatars WHERE user_id = $1 ORDER BY created_at DESC',
        [userId]
      );
      custom = result.rows.map(r => ({
        id: r.id,
        name: r.name,
        gender: r.gender,
        style: r.style,
        thumbnail: r.thumbnail_url,
        sourceImage: r.source_image_url,
        preset: false,
        createdAt: r.created_at
      }));
    }

    res.json({ avatars: [...PRESET_AVATARS, ...custom] });
  } catch (err) {
    console.error('Error listing avatars:', err.message);
    res.status(500).json({ error: 'Failed to list avatars' });
  }
});

// GET /api/avatars/:id
router.get('/:id', async (req, res) => {
  const preset = PRESET_AVATARS.find(a => a.id === req.params.id);
  if (preset) return res.json(preset);

  try {
    const result = await req.db.query('SELECT * FROM avatars WHERE id = $1', [req.params.id]);
    if (!result.rows.length) return res.status(404).json({ error: 'Avatar not found' });
    const r = result.rows[0];
    res.json({
      id: r.id,
      name: r.name,
      gender: r.gender,
      style: r.style,
      thumbnail: r.thumbnail_url,
      sourceImage: r.source_image_url,
      preset: false,
      createdAt: r.created_at
    });
  } catch (err) {
    res.status(500).json({ error: 'Failed to get avatar' });
  }
});

// POST /api/avatars — create custom avatar from uploaded image
router.post('/', async (req, res) => {
  const { userId, name, gender, style, imageUrl } = req.body;

  if (!userId || !imageUrl) {
    return res.status(400).json({ error: 'userId and imageUrl are required' });
  }

  try {
    const id = uuid();
    await req.db.query(
      `INSERT INTO avatars (id, user_id, name, gender, style, source_image_url, thumbnail_url, created_at)
       VALUES ($1, $2, $3, $4, $5, $6, $6, NOW())`,
      [id, userId, name || 'Custom Avatar', gender || 'neutral', style || 'custom', imageUrl]
    );

    res.json({
      id,
      name: name || 'Custom Avatar',
      gender: gender || 'neutral',
      style: style || 'custom',
      thumbnail: imageUrl,
      sourceImage: imageUrl,
      preset: false
    });
  } catch (err) {
    console.error('Error creating avatar:', err.message);
    res.status(500).json({ error: 'Failed to create avatar' });
  }
});

// DELETE /api/avatars/:id
router.delete('/:id', async (req, res) => {
  if (req.params.id.startsWith('avatar-')) {
    return res.status(400).json({ error: 'Cannot delete preset avatars' });
  }

  try {
    await req.db.query('DELETE FROM avatars WHERE id = $1', [req.params.id]);
    res.json({ success: true });
  } catch (err) {
    res.status(500).json({ error: 'Failed to delete avatar' });
  }
});

module.exports = router;
