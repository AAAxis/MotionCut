/**
 * Credit pricing — 1 credit = 1 second of video = ~$0.10
 * 
 * IAP tiers:
 *   100 credits = $9.99
 *   200 credits = $17.99
 *   300 credits = $24.99
 */

// Credits per second of video for each model
// Tuned so 100 promo credits ≈ 1 generation (5s clip)
const MODEL_CREDITS_PER_SECOND = {
  // Budget
  'bytedance/seedance-1-lite': 12,      // 5s = 60 credits
  'wan-video/wan-2.5-t2v-fast': 12,     // 5s = 60 credits
  // Standard
  'bytedance/seedance-1-pro': 16,       // 5s = 80 credits
  'kwaivgi/kling-v1.6-standard': 16,    // 5s = 80 credits
  'kwaivgi/kling-v2.1': 18,             // 5s = 90 credits
  'kwaivgi/kling-v3.0': 20,             // 5s = 100 credits
  // Premium
  'minimax/video-01': 20,               // 5s = 100 credits
  'google/veo-3.1-fast': 20,            // 5s = 100 credits
  'google/veo-3.1': 24,                 // 5s = 120 credits
  'runway/gen-4.5': 24,                 // 5s = 120 credits
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
