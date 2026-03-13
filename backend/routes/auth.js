const express = require('express');
const router = express.Router();

// POST /api/auth/token — Simple auth (exchange external auth for API access)
router.post('/token', async (req, res) => {
  const { externalId, email } = req.body;
  if (!externalId) return res.status(400).json({ error: 'externalId required' });

  // Upsert user
  await req.db.query(
    `INSERT INTO users (external_id, email) VALUES ($1, $2)
     ON CONFLICT (external_id) DO UPDATE SET email = COALESCE($2, users.email)`,
    [externalId, email || null]
  );

  res.json({ ok: true, userId: externalId });
});

// POST /api/auth/expo-web-success — OAuth callback for Expo web
router.post('/expo-web-success', async (req, res) => {
  res.json({ ok: true });
});

module.exports = router;
