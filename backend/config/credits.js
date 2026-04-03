/**
 * Credit pricing — 1 credit = 1 second of video = ~$0.10
 * 
 * IAP tiers:
 *   100 credits = $9.99
 *   200 credits = $17.99
 *   300 credits = $24.99
 */

// Credits per second of video for each model
const MODEL_CREDITS_PER_SECOND = {
  // Budget
  'bytedance/seedance-1-lite': 1,       // $0.04/5s → 5 credits = $0.50
  'wan-video/wan-2.5-t2v-fast': 1,      // $0.05/5s → 5 credits = $0.50
  // Standard
  'bytedance/seedance-1-pro': 2,        // $0.08/5s → 10 credits = $1.00
  'kwaivgi/kling-v1.6-standard': 2,     // $0.15/5s → 10 credits = $1.00
  'kwaivgi/kling-v2.1': 3,              // $0.30/5s → 15 credits = $1.50
  'kwaivgi/kling-v3.0': 4,              // $0.84/5s → 20 credits = $2.00
  // Premium
  'minimax/video-01': 5,                // $0.50/5s → 25 credits = $2.50
  'google/veo-3.1-fast': 5,             // $0.50/5s → 25 credits = $2.50
  'google/veo-3.1': 8,                  // $1.00/5s → 40 credits = $4.00
  'runway/gen-4.5': 8,                  // $1.25/5s → 40 credits = $4.00
};

// Fixed credit costs for non-video operations
const OPERATION_CREDITS = {
  'ad-maker': 10,    // Full ad pipeline (scrape + script + TTS + video + lipsync)
  'tts': 0,          // TTS included in ad cost
  'lipsync': 0,      // Lipsync included in ad cost
};

// IAP product → credits mapping (Apple/Google product IDs)
const IAP_PRODUCTS = {
  'credits_100': 100,
  'credits_200': 200,
  'credits_300': 300,
};

// Free credits for new users
const FREE_CREDITS = 10;

// Rate limiting
const RATE_LIMITS = {
  free: {
    dailyGenerations: 3,      // 3 generations per day
    cooldownSeconds: 60,       // 60s between generations
  },
  paid: {
    dailyGenerations: 50,      // 50/day — generous but not unlimited
    cooldownSeconds: 10,       // 10s cooldown
  },
};

function calculateCost(modelId, durationSeconds) {
  const perSecond = MODEL_CREDITS_PER_SECOND[modelId] || 2; // default 2 credits/sec
  return Math.ceil(perSecond * durationSeconds);
}

module.exports = {
  MODEL_CREDITS_PER_SECOND,
  OPERATION_CREDITS,
  IAP_PRODUCTS,
  FREE_CREDITS,
  RATE_LIMITS,
  calculateCost,
};
