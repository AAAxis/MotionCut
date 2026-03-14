const express = require('express');
const router = express.Router();
const { calculateCost, OPERATION_CREDITS, IAP_PRODUCTS, FREE_CREDITS, MODEL_CREDITS_PER_SECOND, RATE_LIMITS } = require('../config/credits');
const { checkRateLimit } = require('../middleware/rateLimit');

// POST /api/credits/get
router.post('/get', async (req, res) => {
  const { userId } = req.body;
  if (!userId) return res.status(400).json({ error: 'userId required' });

  let result = await req.db.query(
    'SELECT credits, is_subscribed FROM users WHERE external_id = $1',
    [userId]
  );

  if (!result.rows[0]) {
    await req.db.query(
      `INSERT INTO users (external_id, credits) VALUES ($1, $2) ON CONFLICT (external_id) DO NOTHING`,
      [userId, FREE_CREDITS]
    );
    return res.json({ credits: FREE_CREDITS, isSubscribed: false });
  }

  const user = result.rows[0];
  const rateInfo = await checkRateLimit(req.db, userId);
  res.json({
    credits: user.is_subscribed ? -1 : user.credits,
    isSubscribed: user.is_subscribed,
    rateLimit: {
      remaining: rateInfo.remaining ?? 0,
      limit: rateInfo.limit ?? RATE_LIMITS.free.dailyGenerations,
      tier: rateInfo.tier ?? 'free',
      allowed: rateInfo.allowed,
      message: rateInfo.message,
    },
  });
});

// POST /api/credits/check — Check if user has enough credits for a generation
router.post('/check', async (req, res) => {
  const { userId, modelId, duration = 5, operation } = req.body;
  if (!userId) return res.status(400).json({ error: 'userId required' });

  const result = await req.db.query(
    'SELECT credits, is_subscribed FROM users WHERE external_id = $1',
    [userId]
  );

  if (!result.rows[0]) {
    return res.json({ allowed: true, credits: FREE_CREDITS, cost: 0 });
  }

  const user = result.rows[0];
  if (user.is_subscribed) {
    return res.json({ allowed: true, credits: -1, cost: 0, isSubscribed: true });
  }

  let cost;
  if (operation && OPERATION_CREDITS[operation] !== undefined) {
    cost = OPERATION_CREDITS[operation];
  } else {
    cost = calculateCost(modelId || 'bytedance/seedance-1-lite', duration);
  }

  res.json({
    allowed: user.credits >= cost,
    credits: user.credits,
    cost,
    remaining: user.credits - cost,
  });
});

// POST /api/credits/deduct
router.post('/deduct', async (req, res) => {
  const { userId, amount, modelId, duration = 5, operation } = req.body;
  if (!userId) return res.status(400).json({ error: 'userId required' });

  // Calculate cost if not explicitly provided
  let cost = amount;
  if (!cost) {
    if (operation && OPERATION_CREDITS[operation] !== undefined) {
      cost = OPERATION_CREDITS[operation];
    } else {
      cost = calculateCost(modelId || 'bytedance/seedance-1-lite', duration);
    }
  }

  // Check sufficient credits first
  const check = await req.db.query(
    'SELECT credits, is_subscribed FROM users WHERE external_id = $1',
    [userId]
  );

  if (check.rows[0]?.is_subscribed) {
    return res.json({ credits: -1, isSubscribed: true, deducted: 0 });
  }

  if (!check.rows[0] || check.rows[0].credits < cost) {
    return res.status(402).json({
      error: 'Insufficient credits',
      credits: check.rows[0]?.credits || 0,
      cost,
      needed: cost - (check.rows[0]?.credits || 0),
    });
  }

  const result = await req.db.query(
    `UPDATE users SET credits = credits - $1
     WHERE external_id = $2 AND credits >= $1
     RETURNING credits`,
    [cost, userId]
  );

  if (!result.rows[0]) {
    return res.status(402).json({ error: 'Insufficient credits' });
  }

  res.json({ credits: result.rows[0].credits, deducted: cost });
});

// POST /api/credits/add — Add credits (from IAP purchase)
router.post('/add', async (req, res) => {
  const { userId, productId, amount } = req.body;
  if (!userId) return res.status(400).json({ error: 'userId required' });

  let creditsToAdd = amount;
  if (!creditsToAdd && productId) {
    creditsToAdd = IAP_PRODUCTS[productId];
  }
  if (!creditsToAdd) {
    return res.status(400).json({ error: 'productId or amount required' });
  }

  const result = await req.db.query(
    `INSERT INTO users (external_id, credits) VALUES ($1, $2)
     ON CONFLICT (external_id) DO UPDATE SET credits = users.credits + $2
     RETURNING credits`,
    [userId, creditsToAdd]
  );

  console.log(`[Credits] Added ${creditsToAdd} credits to ${userId}, total: ${result.rows[0].credits}`);

  res.json({
    credits: result.rows[0].credits,
    added: creditsToAdd,
  });
});

// GET /api/credits/pricing — Return pricing info for the app
router.get('/pricing', (req, res) => {
  res.json({
    models: Object.entries(MODEL_CREDITS_PER_SECOND).map(([id, perSecond]) => ({
      id,
      creditsPerSecond: perSecond,
      cost5s: perSecond * 5,
      cost10s: perSecond * 10,
    })),
    operations: OPERATION_CREDITS,
    iap: [
      { productId: 'credits_100', credits: 100, price: '$9.99' },
      { productId: 'credits_200', credits: 200, price: '$17.99' },
      { productId: 'credits_300', credits: 300, price: '$24.99' },
    ],
    freeCredits: FREE_CREDITS,
    rateLimits: RATE_LIMITS,
  });
});

// POST /api/credits/subscription
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
