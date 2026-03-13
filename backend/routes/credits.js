const express = require('express');
const router = express.Router();

// POST /api/credits/get
router.post('/get', async (req, res) => {
  const { userId } = req.body;
  if (!userId) return res.status(400).json({ error: 'userId required' });

  let result = await req.db.query(
    'SELECT credits, is_subscribed FROM users WHERE external_id = $1',
    [userId]
  );

  if (!result.rows[0]) {
    // Auto-create user with 3 free credits
    await req.db.query(
      'INSERT INTO users (external_id, credits) VALUES ($1, 3) ON CONFLICT (external_id) DO NOTHING',
      [userId]
    );
    return res.json({ credits: 3, isSubscribed: false });
  }

  const user = result.rows[0];
  res.json({
    credits: user.is_subscribed ? -1 : user.credits, // -1 = unlimited
    isSubscribed: user.is_subscribed,
  });
});

// POST /api/credits/deduct
router.post('/deduct', async (req, res) => {
  const { userId, amount = 1 } = req.body;
  if (!userId) return res.status(400).json({ error: 'userId required' });

  const result = await req.db.query(
    `UPDATE users SET credits = GREATEST(credits - $1, 0)
     WHERE external_id = $2 AND is_subscribed = false
     RETURNING credits`,
    [amount, userId]
  );

  if (!result.rows[0]) {
    return res.json({ credits: -1, isSubscribed: true });
  }

  res.json({ credits: result.rows[0].credits });
});

// POST /api/credits/subscription — Update subscription status (called from RevenueCat webhook)
router.post('/subscription', async (req, res) => {
  const { userId, isSubscribed } = req.body;
  if (!userId) return res.status(400).json({ error: 'userId required' });

  await req.db.query(
    `INSERT INTO users (external_id, is_subscribed) VALUES ($1, $2)
     ON CONFLICT (external_id) DO UPDATE SET is_subscribed = $2`,
    [userId, isSubscribed]
  );

  res.json({ ok: true });
});

module.exports = router;
