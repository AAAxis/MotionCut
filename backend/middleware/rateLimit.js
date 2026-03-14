/**
 * Server-side rate limiting for AI generations.
 * 
 * Uses DB table `user_rate_limits` to track:
 * - daily generation count (resets at midnight UTC)
 * - last generation timestamp (cooldown enforcement)
 *
 * Free users: 3 gens/day, 60s cooldown
 * Paid users (bought credits): 50 gens/day, 10s cooldown
 */
const { RATE_LIMITS } = require('../config/credits');

async function checkRateLimit(db, userId) {
  if (!userId) return { allowed: true };

  // Get user tier
  const userResult = await db.query(
    'SELECT credits, is_subscribed FROM users WHERE external_id = $1',
    [userId]
  );
  
  const user = userResult.rows[0];
  const hasPaid = user && (user.is_subscribed || user.credits > 10); // bought credits = paid
  const limits = hasPaid ? RATE_LIMITS.paid : RATE_LIMITS.free;

  // Get or create rate limit record
  const today = new Date().toISOString().slice(0, 10); // YYYY-MM-DD
  let rl = await db.query(
    'SELECT * FROM user_rate_limits WHERE user_id = $1',
    [userId]
  );

  if (!rl.rows[0]) {
    await db.query(
      `INSERT INTO user_rate_limits (user_id, daily_count, daily_date, last_generation_at)
       VALUES ($1, 0, $2, NULL)
       ON CONFLICT (user_id) DO NOTHING`,
      [userId, today]
    );
    rl = await db.query('SELECT * FROM user_rate_limits WHERE user_id = $1', [userId]);
  }

  const record = rl.rows[0];

  // Reset daily count if new day
  let dailyCount = record.daily_count || 0;
  if (record.daily_date !== today) {
    dailyCount = 0;
    await db.query(
      'UPDATE user_rate_limits SET daily_count = 0, daily_date = $1 WHERE user_id = $2',
      [today, userId]
    );
  }

  // Check daily limit
  if (dailyCount >= limits.dailyGenerations) {
    const resetsIn = getTimeUntilMidnightUTC();
    return {
      allowed: false,
      reason: 'daily_limit',
      message: `Daily limit reached (${limits.dailyGenerations}/day). Resets in ${resetsIn}.`,
      limit: limits.dailyGenerations,
      used: dailyCount,
      resetsIn,
      upgrade: !hasPaid,
    };
  }

  // Check cooldown
  if (record.last_generation_at) {
    const lastGen = new Date(record.last_generation_at);
    const elapsed = (Date.now() - lastGen.getTime()) / 1000;
    if (elapsed < limits.cooldownSeconds) {
      const waitSeconds = Math.ceil(limits.cooldownSeconds - elapsed);
      return {
        allowed: false,
        reason: 'cooldown',
        message: `Please wait ${waitSeconds}s before generating again.`,
        waitSeconds,
        upgrade: !hasPaid,
      };
    }
  }

  return {
    allowed: true,
    remaining: limits.dailyGenerations - dailyCount - 1,
    limit: limits.dailyGenerations,
    used: dailyCount + 1,
    tier: hasPaid ? 'paid' : 'free',
  };
}

async function recordGeneration(db, userId) {
  if (!userId) return;
  const today = new Date().toISOString().slice(0, 10);
  await db.query(
    `INSERT INTO user_rate_limits (user_id, daily_count, daily_date, last_generation_at)
     VALUES ($1, 1, $2, NOW())
     ON CONFLICT (user_id) DO UPDATE SET
       daily_count = CASE WHEN user_rate_limits.daily_date = $2 
         THEN user_rate_limits.daily_count + 1 
         ELSE 1 END,
       daily_date = $2,
       last_generation_at = NOW()`,
    [userId, today]
  );
}

function getTimeUntilMidnightUTC() {
  const now = new Date();
  const midnight = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate() + 1));
  const diff = midnight - now;
  const hours = Math.floor(diff / 3600000);
  const minutes = Math.floor((diff % 3600000) / 60000);
  return `${hours}h ${minutes}m`;
}

module.exports = { checkRateLimit, recordGeneration };
