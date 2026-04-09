/**
 * CreatorAI Cloudflare Worker
 *
 * Proxies: fal.ai (video generation), Replicate (TTS/video)
 * Direct:  Supabase (credits, users, generations, rate limits)
 *
 * Routes:
 *   POST /api/auth/token         — Register/update user
 *   POST /api/credits/get        — Get user credits
 *   POST /api/credits/add        — Add credits (IAP)
 *   POST /api/credits/check      — Check if enough credits
 *   POST /api/credits/deduct     — Deduct credits
 *   POST /api/create/generate    — Start AI video generation (fal.ai)
 *   GET  /api/create/status/:id  — Poll generation status
 *   GET  /health                 — Health check
 */

// ── Config ───────────────────────────────────────────────────────────
// Tuned so 100 promo credits ≈ 1 generation (5s clip)
// Must match the MODELS array in src/components/create/unified-input.tsx.
// Cost is floored to 10 credits per video minimum (see calculateCost).
const MODEL_CREDITS_PER_SECOND = {
  'bytedance/seedance-1-lite': 2,     // 5s = 10  (welcome-pack tier)
  'wan-video/wan-2.5-t2v-fast': 2,    // 5s = 10
  'bytedance/seedance-1-pro': 14,     // 5s = 70
  'kwaivgi/kling-v1.6-standard': 14,  // 5s = 70
  'kwaivgi/kling-v2.1': 16,           // 5s = 80
  'kwaivgi/kling-v3.0': 20,           // 5s = 100
  'minimax/video-01': 24,             // 5s = 120
  'google/veo-3.1-fast': 24,          // 5s = 120
  'google/veo-3.1': 32,               // 5s = 160
  'runway/gen-4.5': 32,               // 5s = 160
};

const FREE_CREDITS = 10;
const RATE_LIMITS = {
  free: { dailyGenerations: 10, cooldownSeconds: 30 },
  paid: { dailyGenerations: 100, cooldownSeconds: 5 },
};

const IAP_PRODUCTS = {
  'credits_10': 10,    // welcome pack — covers 1 Seedance Lite 5s video
  'credits_100': 100,
  'credits_200': 200,
  'credits_300': 300,
  'com.creator.10': 10,
  'com.creator.100': 100,
  'com.creator.200': 200,
  'com.creator.300': 300,
};

function calculateCost(modelId, duration) {
  const perSecond = MODEL_CREDITS_PER_SECOND[modelId] || 2;
  return Math.max(10, Math.ceil(perSecond * duration));
}

// ── Supabase Storage: copy remote file to permanent storage ─────────
const STORAGE_BUCKET = 'generation-inputs';

async function copyToStorage(env, sourceUrl, storagePath, contentType) {
  // Download from fal.media (or wherever).
  const dlRes = await fetch(sourceUrl);
  if (!dlRes.ok) throw new Error(`Download failed: ${dlRes.status}`);
  const blob = await dlRes.arrayBuffer();

  // Upload to Supabase Storage via the S3-compatible REST API.
  const key = env.SUPABASE_SERVICE_KEY || env.SUPABASE_ANON_KEY;
  const uploadUrl = `${env.SUPABASE_URL}/storage/v1/object/${STORAGE_BUCKET}/${storagePath}`;
  const upRes = await fetch(uploadUrl, {
    method: 'POST',
    headers: {
      'apikey': key,
      'Authorization': `Bearer ${key}`,
      'Content-Type': contentType,
      'x-upsert': 'true',
    },
    body: blob,
  });
  if (!upRes.ok) {
    const err = await upRes.text();
    throw new Error(`Upload failed: ${upRes.status} ${err.slice(0, 200)}`);
  }

  // Return the public URL.
  return `${env.SUPABASE_URL}/storage/v1/object/public/${STORAGE_BUCKET}/${storagePath}`;
}

// ── Supabase helpers ─────────────────────────────────────────────────
async function supabase(env, method, table, options = {}) {
  const { filter, body, select, order, single } = options;
  let url = `${env.SUPABASE_URL}/rest/v1/${table}`;

  const params = [];
  if (filter) params.push(filter);
  if (select) params.push(`select=${select}`);
  if (order) params.push(`order=${order}`);
  if (params.length) url += '?' + params.join('&');

  const headers = {
    'apikey': env.SUPABASE_SERVICE_KEY || env.SUPABASE_ANON_KEY,
    'Authorization': `Bearer ${env.SUPABASE_SERVICE_KEY || env.SUPABASE_ANON_KEY}`,
    'Content-Type': 'application/json',
    'Prefer': 'return=representation',
  };

  if (method === 'PATCH' || method === 'DELETE') {
    // Don't override Prefer for these
  }
  if (options.upsert) {
    headers['Prefer'] = 'return=representation,resolution=merge-duplicates';
  }

  const res = await fetch(url, {
    method,
    headers,
    body: body ? JSON.stringify(body) : undefined,
  });

  if (!res.ok) {
    const err = await res.text();
    throw new Error(`Supabase ${method} ${table}: ${res.status} ${err}`);
  }

  const text = await res.text();
  if (!text) return null;
  const data = JSON.parse(text);
  return single ? data[0] : data;
}

async function getUser(env, userId) {
  const rows = await supabase(env, 'GET', 'app_users', {
    filter: `id=eq.${userId}`,
    select: '*',
  });
  return rows?.[0] || null;
}

async function getUserByEmail(env, email) {
  if (!email) return null;
  const rows = await supabase(env, 'GET', 'app_users', {
    filter: `email=eq.${email}`,
    select: '*',
  });
  return rows?.[0] || null;
}

async function upsertUser(env, data) {
  return supabase(env, 'POST', 'app_users', { body: data, upsert: true });
}

// ── fal.ai helpers ───────────────────────────────────────────────────
const FAL_VIDEO_MODEL = 'fal-ai/pixverse/v4/text-to-video';

// Per-model fal.ai endpoint mapping. Keys match the modelId sent from the
// frontend (src/components/create/unified-input.tsx). Each entry provides:
//   - t2vFal: fal endpoint for text-to-video
//   - i2vFal: fal endpoint for image-to-video (optional; falls back to t2vFal)
//   - t2v(prompt, duration): build request body for text-to-video
//   - i2v(prompt, imageUrl, duration): build request body for image-to-video
// NOTE: Endpoint paths and parameter names are the current best guess from
// fal.ai docs as of 2026-04. If a model returns 404 or "invalid input",
// verify the path at https://fal.ai/models and adjust here.
const MODEL_CONFIGS = {
  // ── Budget ──
  'bytedance/seedance-1-lite': {
    t2vFal: 'fal-ai/bytedance/seedance/v1/lite/text-to-video',
    i2vFal: 'fal-ai/bytedance/seedance/v1/lite/image-to-video',
    t2v: (prompt, duration) => ({ prompt, duration: String(duration <= 5 ? 5 : 10), aspect_ratio: '9:16', resolution: '720p' }),
    i2v: (prompt, imageUrl, duration) => ({ prompt, image_url: imageUrl, duration: String(duration <= 5 ? 5 : 10), aspect_ratio: '9:16', resolution: '720p' }),
  },
  'wan-video/wan-2.5-t2v-fast': {
    t2vFal: 'fal-ai/wan/v2.5/text-to-video/fast',
    i2vFal: 'fal-ai/wan/v2.5/image-to-video/fast',
    t2v: (prompt, duration) => ({ prompt, duration: String(duration <= 5 ? 5 : 8), aspect_ratio: '9:16', resolution: '720p' }),
    i2v: (prompt, imageUrl, duration) => ({ prompt, image_url: imageUrl, duration: String(duration <= 5 ? 5 : 8), aspect_ratio: '9:16', resolution: '720p' }),
  },
  // ── Standard ──
  'bytedance/seedance-1-pro': {
    t2vFal: 'fal-ai/bytedance/seedance/v1/pro/text-to-video',
    i2vFal: 'fal-ai/bytedance/seedance/v1/pro/image-to-video',
    t2v: (prompt, duration) => ({ prompt, duration: String(duration <= 5 ? 5 : 10), aspect_ratio: '9:16', resolution: '1080p' }),
    i2v: (prompt, imageUrl, duration) => ({ prompt, image_url: imageUrl, duration: String(duration <= 5 ? 5 : 10), aspect_ratio: '9:16', resolution: '1080p' }),
  },
  'kwaivgi/kling-v1.6-standard': {
    t2vFal: 'fal-ai/kling-video/v1.6/standard/text-to-video',
    i2vFal: 'fal-ai/kling-video/v1.6/standard/image-to-video',
    t2v: (prompt, duration) => ({ prompt, duration: String(duration <= 5 ? 5 : 10), aspect_ratio: '9:16' }),
    i2v: (prompt, imageUrl, duration) => ({ prompt, image_url: imageUrl, duration: String(duration <= 5 ? 5 : 10), aspect_ratio: '9:16' }),
  },
  'kwaivgi/kling-v2.1': {
    t2vFal: 'fal-ai/kling-video/v2.1/master/text-to-video',
    i2vFal: 'fal-ai/kling-video/v2.1/master/image-to-video',
    t2v: (prompt, duration) => ({ prompt, duration: String(duration <= 5 ? 5 : 10), aspect_ratio: '9:16' }),
    i2v: (prompt, imageUrl, duration) => ({ prompt, image_url: imageUrl, duration: String(duration <= 5 ? 5 : 10), aspect_ratio: '9:16' }),
  },
  'kwaivgi/kling-v3.0': {
    t2vFal: 'fal-ai/kling-video/v2.5-turbo/pro/text-to-video',
    i2vFal: 'fal-ai/kling-video/v2.5-turbo/pro/image-to-video',
    t2v: (prompt, duration) => ({ prompt, duration: String(duration <= 5 ? 5 : 10), aspect_ratio: '9:16' }),
    i2v: (prompt, imageUrl, duration) => ({ prompt, image_url: imageUrl, duration: String(duration <= 5 ? 5 : 10), aspect_ratio: '9:16' }),
  },
  // ── Premium ──
  'minimax/video-01': {
    t2vFal: 'fal-ai/minimax/hailuo-02/standard/text-to-video',
    i2vFal: 'fal-ai/minimax/hailuo-02/standard/image-to-video',
    t2v: (prompt) => ({ prompt, prompt_optimizer: true }),
    i2v: (prompt, imageUrl) => ({ prompt, image_url: imageUrl, prompt_optimizer: true }),
  },
  'google/veo-3.1-fast': {
    t2vFal: 'fal-ai/veo3/fast',
    i2vFal: 'fal-ai/veo3/fast/image-to-video',
    t2v: (prompt) => ({ prompt, aspect_ratio: '9:16', generate_audio: true }),
    i2v: (prompt, imageUrl) => ({ prompt, image_url: imageUrl, aspect_ratio: '9:16', generate_audio: true }),
  },
  'google/veo-3.1': {
    t2vFal: 'fal-ai/veo3',
    i2vFal: 'fal-ai/veo3/image-to-video',
    t2v: (prompt) => ({ prompt, aspect_ratio: '9:16', generate_audio: true }),
    i2v: (prompt, imageUrl) => ({ prompt, image_url: imageUrl, aspect_ratio: '9:16', generate_audio: true }),
  },
  'runway/gen-4.5': {
    // Runway Gen-4 on fal: image-to-video is the primary mode.
    t2vFal: 'fal-ai/runway-gen4/turbo/image-to-video',
    i2vFal: 'fal-ai/runway-gen4/turbo/image-to-video',
    t2v: (prompt, duration) => ({ prompt, duration: duration <= 5 ? 5 : 10, aspect_ratio: '9:16' }),
    i2v: (prompt, imageUrl, duration) => ({ prompt, image_url: imageUrl, duration: duration <= 5 ? 5 : 10, aspect_ratio: '9:16' }),
  },
};

// Default config used when an unknown modelId is sent.
const DEFAULT_MODEL_CONFIG = MODEL_CONFIGS['bytedance/seedance-1-lite'];

async function falSubmit(env, modelId, input) {
  const url = `https://queue.fal.run/${modelId}`;
  const res = await fetch(url, {
    method: 'POST',
    headers: {
      'Authorization': `Key ${env.FAL_KEY}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify(input),
  });
  const data = await safeJson(res);
  console.log('[falSubmit]', { url, httpStatus: res.status, data: JSON.stringify(data).slice(0, 500) });
  return data;
}

// Compute the fal queue path for status/result polling. fal.ai expects the
// SAME path that was used to submit (no stripping). Older pixverse model used
// a shortened base, but the modern seedance/kling/veo endpoints require the
// full path.
function falBasePath(modelId) {
  return modelId;
}

async function safeJson(res) {
  const text = await res.text();
  if (!text) return {};
  try { return JSON.parse(text); } catch { return { _raw: text.slice(0, 300) }; }
}

// Try multiple candidate base paths until one returns a non-405/404. fal.ai
// queue path conventions vary per model, so we try the full submit path first,
// then progressively shorter prefixes.
function statusCandidates(modelId) {
  const c = new Set();
  c.add(modelId);
  // Strip trailing /text-to-video or /image-to-video
  c.add(modelId.replace(/\/(text-to-video|image-to-video)$/, ''));
  // Strip /v{ver}/... onwards
  c.add(modelId.replace(/\/v[\d.]+\/.*$/, ''));
  // Strip everything after the second segment (e.g. fal-ai/seedance)
  const parts = modelId.split('/');
  if (parts.length >= 2) c.add(parts.slice(0, 2).join('/'));
  return [...c];
}

async function falStatus(env, modelId, requestId) {
  for (const basePath of statusCandidates(modelId)) {
    const url = `https://queue.fal.run/${basePath}/requests/${requestId}/status`;
    const res = await fetch(url, { headers: { 'Authorization': `Key ${env.FAL_KEY}` } });
    if (res.ok) {
      return await safeJson(res);
    }
    if (res.status !== 404 && res.status !== 405) {
      // Real error — return the parsed body
      const data = await safeJson(res);
      console.error('[falStatus] non-ok', { url, httpStatus: res.status, body: JSON.stringify(data).slice(0, 300) });
      return data;
    }
    // Otherwise (404/405), try the next candidate.
  }
  console.error('[falStatus] all candidates failed', { modelId, requestId, candidates: statusCandidates(modelId) });
  return {};
}

async function falResult(env, modelId, requestId) {
  for (const basePath of statusCandidates(modelId)) {
    const url = `https://queue.fal.run/${basePath}/requests/${requestId}`;
    const res = await fetch(url, { headers: { 'Authorization': `Key ${env.FAL_KEY}` } });
    if (res.ok) return await safeJson(res);
    if (res.status !== 404 && res.status !== 405) {
      const data = await safeJson(res);
      console.error('[falResult] non-ok', { url, httpStatus: res.status, body: JSON.stringify(data).slice(0, 300) });
      return data;
    }
  }
  console.error('[falResult] all candidates failed', { modelId, requestId });
  return {};
}

// ── Rate limiting ────────────────────────────────────────────────────
async function checkRateLimit(env, userId) {
  const user = await getUser(env, userId);
  const hasPaid = user && (user.is_subscribed || (user.credits || 0) > 10);
  const limits = hasPaid ? RATE_LIMITS.paid : RATE_LIMITS.free;

  const today = new Date().toISOString().slice(0, 10);

  let rows = await supabase(env, 'GET', 'rate_limits', {
    filter: `user_id=eq.${userId}`,
    select: '*',
  });

  let record = rows?.[0];
  if (!record) {
    await supabase(env, 'POST', 'rate_limits', {
      body: { user_id: userId, daily_count: 0, daily_date: today },
      upsert: true,
    });
    return { allowed: true, remaining: limits.dailyGenerations, limit: limits.dailyGenerations, tier: hasPaid ? 'paid' : 'free' };
  }

  let dailyCount = record.daily_count || 0;
  if (record.daily_date !== today) {
    dailyCount = 0;
    await supabase(env, 'PATCH', 'rate_limits', {
      filter: `user_id=eq.${userId}`,
      body: { daily_count: 0, daily_date: today },
    });
  }

  if (dailyCount >= limits.dailyGenerations) {
    return { allowed: false, reason: 'daily_limit', message: `Daily limit reached (${limits.dailyGenerations}/day)`, limit: limits.dailyGenerations, used: dailyCount };
  }

  if (record.last_generation_at) {
    const elapsed = (Date.now() - new Date(record.last_generation_at).getTime()) / 1000;
    if (elapsed < limits.cooldownSeconds) {
      return { allowed: false, reason: 'cooldown', message: `Wait ${Math.ceil(limits.cooldownSeconds - elapsed)}s`, waitSeconds: Math.ceil(limits.cooldownSeconds - elapsed) };
    }
  }

  return { allowed: true, remaining: limits.dailyGenerations - dailyCount - 1, limit: limits.dailyGenerations, tier: hasPaid ? 'paid' : 'free' };
}

async function recordGeneration(env, userId) {
  const today = new Date().toISOString().slice(0, 10);
  const rows = await supabase(env, 'GET', 'rate_limits', { filter: `user_id=eq.${userId}` });
  if (rows?.[0]) {
    const newCount = (rows[0].daily_date === today ? rows[0].daily_count : 0) + 1;
    await supabase(env, 'PATCH', 'rate_limits', {
      filter: `user_id=eq.${userId}`,
      body: { daily_count: newCount, daily_date: today, last_generation_at: new Date().toISOString() },
    });
  } else {
    await supabase(env, 'POST', 'rate_limits', {
      body: { user_id: userId, daily_count: 1, daily_date: today, last_generation_at: new Date().toISOString() },
      upsert: true,
    });
  }
}

// ── Route handlers ───────────────────────────────────────────────────
async function handleAuth(request, env) {
  const { externalId, email, firebaseUid, fcmToken, platform, displayName, avatarUrl } = await request.json();
  if (!externalId) return json({ error: 'externalId required' }, 400);

  // Check if user already exists by ID
  let existing = await getUser(env, externalId);

  // If not found by ID, check by email — merge accounts across platforms
  if (!existing && email) {
    const emailUser = await getUserByEmail(env, email);
    if (emailUser) {
      // Migrate old account: update the ID to Firebase UID, keep credits
      await supabase(env, 'PATCH', 'app_users', {
        filter: `id=eq.${emailUser.id}`,
        body: {
          id: externalId,
          firebase_uid: firebaseUid || undefined,
          fcm_token: fcmToken || undefined,
          platform: platform || undefined,
          display_name: displayName || emailUser.display_name,
          avatar_url: avatarUrl || emailUser.avatar_url,
        },
      });
      existing = { ...emailUser, id: externalId };
    }
  }

  if (existing) {
    // Update profile fields without overwriting credits
    await upsertUser(env, {
      id: externalId,
      email: email || undefined,
      firebase_uid: firebaseUid || undefined,
      fcm_token: fcmToken || undefined,
      platform: platform || undefined,
      display_name: displayName || undefined,
      avatar_url: avatarUrl || undefined,
    });
  } else {
    // New user — give free credits
    await upsertUser(env, {
      id: externalId,
      email: email || undefined,
      firebase_uid: firebaseUid || undefined,
      fcm_token: fcmToken || undefined,
      platform: platform || undefined,
      display_name: displayName || undefined,
      avatar_url: avatarUrl || undefined,
      credits: FREE_CREDITS,
    });
  }

  return json({ ok: true, userId: externalId, credits: existing?.credits ?? FREE_CREDITS });
}

async function handleCreditsGet(request, env) {
  const { userId, email } = await request.json();
  if (!userId) return json({ error: 'userId required' }, 400);

  let user = await getUser(env, userId);

  // Fallback: find by email if not found by ID
  if (!user && email) {
    user = await getUserByEmail(env, email);
    if (user && user.id !== userId) {
      // Migrate old record to new Firebase UID
      await supabase(env, 'PATCH', 'app_users', {
        filter: `id=eq.${user.id}`,
        body: { id: userId },
      });
      user.id = userId;
    }
  }

  if (!user) {
    await upsertUser(env, { id: userId, email: email || undefined, credits: FREE_CREDITS });
    return json({ credits: FREE_CREDITS, isSubscribed: false });
  }

  // Fix users created without credits (e.g. old direct Supabase writes)
  if (user.credits == null) {
    await upsertUser(env, { id: userId, credits: FREE_CREDITS });
    user.credits = FREE_CREDITS;
  }

  const rateInfo = await checkRateLimit(env, userId);
  return json({
    credits: user.is_subscribed ? -1 : user.credits,
    isSubscribed: user.is_subscribed || false,
    rateLimit: rateInfo,
  });
}

async function handleCreditsAdd(request, env) {
  const { userId, productId, amount } = await request.json();
  if (!userId) return json({ error: 'userId required' }, 400);

  let creditsToAdd = amount;
  if (!creditsToAdd && productId) creditsToAdd = IAP_PRODUCTS[productId];
  if (!creditsToAdd) return json({ error: 'productId or amount required' }, 400);

  let user = await getUser(env, userId);
  const currentCredits = user?.credits || 0;
  const newCredits = currentCredits + creditsToAdd;

  await upsertUser(env, { id: userId, credits: newCredits });
  return json({ credits: newCredits, added: creditsToAdd });
}

async function handleCreditsCheck(request, env) {
  const { userId, modelId, duration = 5 } = await request.json();
  if (!userId) return json({ error: 'userId required' }, 400);

  const user = await getUser(env, userId);
  if (!user) return json({ allowed: true, credits: FREE_CREDITS, cost: 0 });
  if (user.is_subscribed) return json({ allowed: true, credits: -1, cost: 0, isSubscribed: true });

  const cost = calculateCost(modelId || 'bytedance/seedance-1-lite', duration);
  return json({ allowed: (user.credits || 0) >= cost, credits: user.credits || 0, cost });
}

async function handleCreditsDeduct(request, env) {
  const { userId, amount, modelId, duration = 5 } = await request.json();
  if (!userId) return json({ error: 'userId required' }, 400);

  const cost = amount || calculateCost(modelId || 'bytedance/seedance-1-lite', duration);
  const user = await getUser(env, userId);

  if (user?.is_subscribed) return json({ credits: -1, isSubscribed: true, deducted: 0 });
  if (!user || (user.credits || 0) < cost) return json({ error: 'Insufficient credits', credits: user?.credits || 0, cost }, 402);

  const newCredits = (user.credits || 0) - cost;
  await supabase(env, 'PATCH', 'app_users', {
    filter: `id=eq.${userId}`,
    body: { credits: newCredits },
  });

  return json({ credits: newCredits, deducted: cost });
}

async function handlePromoRedeem(request, env) {
  const { code, userEmail } = await request.json();
  if (!code || !userEmail) {
    return json({ error: 'code and userEmail are required' }, 400);
  }
  const codeKey = String(code).trim().toUpperCase();
  const emailKey = String(userEmail).trim().toLowerCase();

  // Look up the promo code.
  const codeRows = await supabase(env, 'GET', 'promo_codes', {
    filter: `code=eq.${codeKey}`,
    select: '*',
  });
  const promo = codeRows?.[0];
  if (!promo) return json({ error: 'Invalid code' }, 404);
  if (!promo.active) return json({ error: 'Code is no longer active' }, 410);
  if (promo.expires_at && new Date(promo.expires_at) < new Date()) {
    return json({ error: 'Code has expired' }, 410);
  }
  if (promo.max_uses != null && promo.used_count >= promo.max_uses) {
    return json({ error: 'Code is fully redeemed' }, 410);
  }

  // Already redeemed by this email?
  const existing = await supabase(env, 'GET', 'promo_redemptions', {
    filter: `code=eq.${codeKey}&user_email=eq.${emailKey}`,
    select: 'id',
  });
  if (existing?.length > 0) {
    return json({ error: 'You already redeemed this code' }, 409);
  }

  // Find or create the app_users row by email.
  const userRows = await supabase(env, 'GET', 'app_users', {
    filter: `email=eq.${emailKey}`,
    select: '*',
  });
  let user = userRows?.[0];
  if (!user) {
    const created = await supabase(env, 'POST', 'app_users', {
      body: { email: emailKey, credits: FREE_CREDITS, platform: 'web' },
      upsert: true,
    });
    user = Array.isArray(created) ? created[0] : created;
  }

  const newCredits = (user?.credits || 0) + promo.credits;

  // Apply: increment user credits, record redemption, bump used_count.
  await supabase(env, 'PATCH', 'app_users', {
    filter: `email=eq.${emailKey}`,
    body: { credits: newCredits },
  });
  await supabase(env, 'POST', 'promo_redemptions', {
    body: { code: codeKey, user_email: emailKey, credits_granted: promo.credits },
  });
  await supabase(env, 'PATCH', 'promo_codes', {
    filter: `code=eq.${codeKey}`,
    body: { used_count: (promo.used_count || 0) + 1 },
  });

  return json({ ok: true, creditsGranted: promo.credits, totalCredits: newCredits });
}

async function handleCreateGenerate(request, env) {
  const { modelId, prompt, imageUrl, duration = 5, userId, userEmail } = await request.json();
  if (!prompt) return json({ error: 'prompt is required' }, 400);

  // Rate limit
  if (userId) {
    const rateCheck = await checkRateLimit(env, userId);
    if (!rateCheck.allowed) return json(rateCheck, 429);
  }

  // Credit check + deduct.
  // SOURCE OF TRUTH: a single app_users row keyed by email (lowercased).
  // If no row exists yet for this email, create one with FREE_CREDITS.
  if (userEmail) {
    const emailKey = String(userEmail).trim().toLowerCase();
    let rows = (await supabase(env, 'GET', 'app_users', {
      filter: `email=eq.${emailKey}`,
      select: '*',
    })) || [];

    let user = rows[0];
    if (!user) {
      // Create the row.
      const created = await supabase(env, 'POST', 'app_users', {
        body: { id: userId, email: emailKey, credits: FREE_CREDITS, platform: 'web' },
        upsert: true,
      });
      user = Array.isArray(created) ? created[0] : created;
      console.log('[credits] created new app_users row', { email: emailKey, credits: FREE_CREDITS });
    }

    console.log('[credits] lookup', {
      email: emailKey,
      rowId: user?.id,
      credits: user?.credits,
      isSubscribed: user?.is_subscribed,
      duplicateRows: rows.length,
    });

    if (user && !user.is_subscribed) {
      const cost = calculateCost(modelId || 'bytedance/seedance-1-lite', duration);
      const available = user.credits || 0;
      console.log('[credits] check', { cost, available, modelId, duration });
      if (available < cost) {
        return json({ error: 'Insufficient credits', credits: available, cost }, 402);
      }
      await supabase(env, 'PATCH', 'app_users', {
        filter: `email=eq.${emailKey}`,
        body: { credits: available - cost },
      });
    }
  } else {
    console.warn('[credits] no userEmail in request — skipping credit check');
  }

  // Pick model + build input
  const hasImage = !!imageUrl;
  let selectedModel = modelId && MODEL_CONFIGS[modelId] ? modelId : 'bytedance/seedance-1-lite';
  const config = MODEL_CONFIGS[selectedModel] || DEFAULT_MODEL_CONFIG;
  let input;
  let falModelId;

  if (hasImage) {
    input = config.i2v(prompt, imageUrl, duration);
    falModelId = config.i2vFal || config.t2vFal;
  } else {
    input = config.t2v(prompt, duration);
    falModelId = config.t2vFal;
  }

  // Submit to fal.ai queue
  const falResponse = await falSubmit(env, falModelId, input);

  if (falResponse.detail || falResponse.error) {
    return json({ error: falResponse.detail || falResponse.error }, 500);
  }

  const id = crypto.randomUUID();

  // Save to Supabase
  await supabase(env, 'POST', 'ai_generations', {
    body: {
      id,
      user_id: userId || null,
      model_id: selectedModel,
      fal_model_id: falModelId,
      fal_request_id: falResponse.request_id,
      mode: hasImage ? 'image-to-video' : 'text-to-video',
      prompt,
      image_url: imageUrl || null,
      duration,
      status: 'processing',
    },
    upsert: true,
  });

  if (userId) await recordGeneration(env, userId);

  return json({ success: true, id, mode: hasImage ? 'image-to-video' : 'text-to-video', model: selectedModel, status: 'processing' });
}

async function handleCreateStatus(id, env) {
  const rows = await supabase(env, 'GET', 'ai_generations', {
    filter: `id=eq.${id}`,
    select: '*',
  });

  if (!rows?.length) return json({ error: 'Not found' }, 404);
  const gen = rows[0];

  // Poll fal.ai if still processing
  if (gen.status !== 'succeeded' && gen.status !== 'failed') {
    const status = await falStatus(env, gen.fal_model_id, gen.fal_request_id);

    if (status.status === 'COMPLETED') {
      const result = await falResult(env, gen.fal_model_id, gen.fal_request_id);
      // Different fal models return result in different shapes — try them all.
      let outputUrl =
        result?.video?.url ||
        result?.output?.url ||
        result?.videos?.[0]?.url ||
        result?.video_url ||
        result?.output_url ||
        result?.url ||
        (Array.isArray(result?.output) ? result.output[0] : null) ||
        null;

      // Extract thumbnail from fal result — models return it under different keys.
      let thumbnailUrl =
        result?.thumbnail?.url ||
        result?.thumbnail_url ||
        result?.thumbnails?.[0]?.url ||
        result?.video?.thumbnail_url ||
        result?.poster_url ||
        null;

      if (!outputUrl) {
        console.error('[handleCreateStatus] COMPLETED but no outputUrl. Result:', JSON.stringify(result).slice(0, 500));
      }

      // ── Persist to Supabase Storage so URLs never expire ────────────
      if (outputUrl) {
        try {
          const permanent = await copyToStorage(env, outputUrl, `videos/${id}.mp4`, 'video/mp4');
          if (permanent) {
            console.log('[persist] video saved:', permanent);
            outputUrl = permanent;
          }
        } catch (e) {
          console.error('[persist] video copy failed:', e.message);
          // Keep the fal URL as fallback.
        }
      }
      if (thumbnailUrl) {
        try {
          const permanent = await copyToStorage(env, thumbnailUrl, `thumbnails/${id}.jpg`, 'image/jpeg');
          if (permanent) {
            console.log('[persist] thumbnail saved:', permanent);
            thumbnailUrl = permanent;
          }
        } catch (e) {
          console.error('[persist] thumbnail copy failed:', e.message);
        }
      }
      // If no thumbnail from fal, generate one from the video via ffmpeg?
      // Not possible in CF Worker — the frontend fallback (<video preload=metadata>)
      // handles it, and the video URL is now permanent so it won't die.

      await supabase(env, 'PATCH', 'ai_generations', {
        filter: `id=eq.${id}`,
        body: { status: 'succeeded', output_url: outputUrl, thumbnail_url: thumbnailUrl, completed_at: new Date().toISOString() },
      });
      gen.status = 'succeeded';
      gen.output_url = outputUrl;
      gen.thumbnail_url = thumbnailUrl;
    } else if (status.status === 'FAILED') {
      await supabase(env, 'PATCH', 'ai_generations', {
        filter: `id=eq.${id}`,
        body: { status: 'failed', error: status.error || 'Generation failed', completed_at: new Date().toISOString() },
      });
      gen.status = 'failed';
      gen.error = status.error;
    }
    // else still IN_QUEUE or IN_PROGRESS — return current status
  }

  return json({
    id: gen.id,
    status: gen.status,
    mode: gen.mode,
    model: gen.model_id,
    prompt: gen.prompt,
    outputUrl: gen.output_url,
    thumbnailUrl: gen.thumbnail_url || null,
    error: gen.error,
    duration: gen.duration,
    createdAt: gen.created_at,
    completedAt: gen.completed_at,
  });
}

// ── Router ───────────────────────────────────────────────────────────
function json(data, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { 'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*' },
  });
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    const path = url.pathname;

    // CORS preflight
    if (request.method === 'OPTIONS') {
      return new Response(null, {
        headers: {
          'Access-Control-Allow-Origin': '*',
          'Access-Control-Allow-Methods': 'GET, POST, PATCH, DELETE, OPTIONS',
          'Access-Control-Allow-Headers': 'Content-Type, Authorization',
        },
      });
    }

    try {
      // Health
      if (path === '/health') return json({ status: 'ok', time: new Date().toISOString() });

      // Auth
      if (path === '/api/auth/token' && request.method === 'POST') return handleAuth(request, env);

      // Credits
      if (path === '/api/credits/get' && request.method === 'POST') return handleCreditsGet(request, env);
      if (path === '/api/credits/add' && request.method === 'POST') return handleCreditsAdd(request, env);
      if (path === '/api/credits/check' && request.method === 'POST') return handleCreditsCheck(request, env);
      if (path === '/api/credits/deduct' && request.method === 'POST') return handleCreditsDeduct(request, env);
      if (path === '/api/promo/redeem' && request.method === 'POST') return handlePromoRedeem(request, env);

      // AI Generation (fal.ai proxy)
      if (path === '/api/create/generate' && request.method === 'POST') return handleCreateGenerate(request, env);
      if (path.startsWith('/api/create/status/') && request.method === 'GET') {
        const id = path.split('/').pop();
        return handleCreateStatus(id, env);
      }

      return json({ error: 'Not found' }, 404);
    } catch (err) {
      console.error('Worker error:', err);
      return json({ error: err.message }, 500);
    }
  },
};
