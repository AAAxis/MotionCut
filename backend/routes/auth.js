const express = require('express');
const router = express.Router();

// POST /api/auth/token — Simple auth (exchange external auth for API access)
router.post('/token', async (req, res) => {
  const { externalId, email, firebaseUid, fcmToken, platform, displayName, avatarUrl } = req.body;
  if (!externalId) return res.status(400).json({ error: 'externalId required' });

  // Upsert user with optional Firebase + FCM fields
  await req.db.query(
    `INSERT INTO users (external_id, email, firebase_uid, fcm_token, platform, display_name, avatar_url)
     VALUES ($1, $2, $3, $4, $5, $6, $7)
     ON CONFLICT (external_id) DO UPDATE SET
       email = COALESCE($2, users.email),
       firebase_uid = COALESCE($3, users.firebase_uid),
       fcm_token = COALESCE($4, users.fcm_token),
       platform = COALESCE($5, users.platform),
       display_name = COALESCE($6, users.display_name),
       avatar_url = COALESCE($7, users.avatar_url)`,
    [externalId, email || null, firebaseUid || null, fcmToken || null, platform || null, displayName || null, avatarUrl || null]
  );

  res.json({ ok: true, userId: externalId });
});

// POST /api/auth/expo-web-success — OAuth callback for Expo web
router.post('/expo-web-success', async (req, res) => {
  res.json({ ok: true });
});

module.exports = router;
