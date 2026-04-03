var __defProp = Object.defineProperty;
var __name = (target, value) => __defProp(target, "name", { value, configurable: true });

// src/index.js
var MODEL_CREDITS_PER_SECOND = {
  "bytedance/seedance-1-lite": 1,
  "wan-video/wan-2.5-t2v-fast": 1,
  "bytedance/seedance-1-pro": 2,
  "kwaivgi/kling-v1.6-standard": 2,
  "kwaivgi/kling-v2.1": 3,
  "kwaivgi/kling-v3.0": 4,
  "minimax/video-01": 5,
  "google/veo-3.1-fast": 5,
  "google/veo-3.1": 8,
  "runway/gen-4.5": 8
};
var FREE_CREDITS = 10;
var RATE_LIMITS = {
  free: { dailyGenerations: 3, cooldownSeconds: 60 },
  paid: { dailyGenerations: 50, cooldownSeconds: 10 }
};
var IAP_PRODUCTS = {
  "credits_100": 100,
  "credits_200": 200,
  "credits_300": 300,
  "com.creator.100": 100,
  "com.creator.200": 200,
  "com.creator.300": 300
};
function calculateCost(modelId, duration) {
  const perSecond = MODEL_CREDITS_PER_SECOND[modelId] || 2;
  return Math.ceil(perSecond * duration);
}
__name(calculateCost, "calculateCost");
async function supabase(env, method, table, options = {}) {
  const { filter, body, select, order, single } = options;
  let url = `${env.SUPABASE_URL}/rest/v1/${table}`;
  const params = [];
  if (filter) params.push(filter);
  if (select) params.push(`select=${select}`);
  if (order) params.push(`order=${order}`);
  if (params.length) url += "?" + params.join("&");
  const headers = {
    "apikey": env.SUPABASE_SERVICE_KEY || env.SUPABASE_ANON_KEY,
    "Authorization": `Bearer ${env.SUPABASE_SERVICE_KEY || env.SUPABASE_ANON_KEY}`,
    "Content-Type": "application/json",
    "Prefer": "return=representation"
  };
  if (method === "PATCH" || method === "DELETE") {
  }
  if (options.upsert) {
    headers["Prefer"] = "return=representation,resolution=merge-duplicates";
  }
  const res = await fetch(url, {
    method,
    headers,
    body: body ? JSON.stringify(body) : void 0
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
__name(supabase, "supabase");
async function getUser(env, userId) {
  const rows = await supabase(env, "GET", "app_users", {
    filter: `id=eq.${userId}`,
    select: "*"
  });
  return rows?.[0] || null;
}
__name(getUser, "getUser");
async function getUserByEmail(env, email) {
  if (!email) return null;
  const rows = await supabase(env, "GET", "app_users", {
    filter: `email=eq.${email}`,
    select: "*"
  });
  return rows?.[0] || null;
}
__name(getUserByEmail, "getUserByEmail");
async function upsertUser(env, data) {
  return supabase(env, "POST", "app_users", { body: data, upsert: true });
}
__name(upsertUser, "upsertUser");
var MODEL_CONFIGS = {
  "bytedance/seedance-1-lite": {
    fal: "fal-ai/pixverse/v4/text-to-video",
    t2v: /* @__PURE__ */ __name((prompt, duration) => ({ prompt, duration: duration <= 5 ? "5" : "8", aspect_ratio: "9:16", quality: "high" }), "t2v"),
    i2v: /* @__PURE__ */ __name((prompt, imageUrl, duration) => ({ prompt, image: imageUrl, duration: duration <= 5 ? "5" : "8", aspect_ratio: "9:16" }), "i2v")
  },
  "bytedance/seedance-1-pro": {
    fal: "fal-ai/pixverse/v4/text-to-video",
    t2v: /* @__PURE__ */ __name((prompt, duration) => ({ prompt, duration: duration <= 5 ? "5" : "8", aspect_ratio: "9:16", quality: "high" }), "t2v"),
    i2v: /* @__PURE__ */ __name((prompt, imageUrl, duration) => ({ prompt, image: imageUrl, duration: duration <= 5 ? "5" : "8", aspect_ratio: "9:16" }), "i2v")
  },
  "minimax/video-01": {
    fal: "fal-ai/pixverse/v4/text-to-video",
    t2v: /* @__PURE__ */ __name((prompt) => ({ prompt, duration: "5", aspect_ratio: "9:16", quality: "high" }), "t2v"),
    i2v: /* @__PURE__ */ __name((prompt, imageUrl) => ({ prompt, image: imageUrl, duration: "5", aspect_ratio: "9:16" }), "i2v")
  },
  "kwaivgi/kling-v2.1": {
    fal: "fal-ai/pixverse/v4/text-to-video",
    t2v: /* @__PURE__ */ __name((prompt, duration) => ({ prompt, duration: duration <= 5 ? "5" : "8", aspect_ratio: "9:16", quality: "high" }), "t2v"),
    i2v: /* @__PURE__ */ __name((prompt, imageUrl, duration) => ({ prompt, image: imageUrl, duration: duration <= 5 ? "5" : "8", aspect_ratio: "9:16" }), "i2v")
  }
};
async function falSubmit(env, modelId, input) {
  const res = await fetch(`https://queue.fal.run/${modelId}`, {
    method: "POST",
    headers: {
      "Authorization": `Key ${env.FAL_KEY}`,
      "Content-Type": "application/json"
    },
    body: JSON.stringify(input)
  });
  return res.json();
}
__name(falSubmit, "falSubmit");
async function falStatus(env, modelId, requestId) {
  const basePath = modelId.replace(/\/v\d+\/.*$/, "");
  const res = await fetch(`https://queue.fal.run/${basePath}/requests/${requestId}/status`, {
    headers: { "Authorization": `Key ${env.FAL_KEY}` }
  });
  return res.json();
}
__name(falStatus, "falStatus");
async function falResult(env, modelId, requestId) {
  const basePath = modelId.replace(/\/v\d+\/.*$/, "");
  const res = await fetch(`https://queue.fal.run/${basePath}/requests/${requestId}`, {
    headers: { "Authorization": `Key ${env.FAL_KEY}` }
  });
  return res.json();
}
__name(falResult, "falResult");
async function checkRateLimit(env, userId) {
  const user = await getUser(env, userId);
  const hasPaid = user && (user.is_subscribed || (user.credits || 0) > 10);
  const limits = hasPaid ? RATE_LIMITS.paid : RATE_LIMITS.free;
  const today = (/* @__PURE__ */ new Date()).toISOString().slice(0, 10);
  let rows = await supabase(env, "GET", "rate_limits", {
    filter: `user_id=eq.${userId}`,
    select: "*"
  });
  let record = rows?.[0];
  if (!record) {
    await supabase(env, "POST", "rate_limits", {
      body: { user_id: userId, daily_count: 0, daily_date: today },
      upsert: true
    });
    return { allowed: true, remaining: limits.dailyGenerations, limit: limits.dailyGenerations, tier: hasPaid ? "paid" : "free" };
  }
  let dailyCount = record.daily_count || 0;
  if (record.daily_date !== today) {
    dailyCount = 0;
    await supabase(env, "PATCH", "rate_limits", {
      filter: `user_id=eq.${userId}`,
      body: { daily_count: 0, daily_date: today }
    });
  }
  if (dailyCount >= limits.dailyGenerations) {
    return { allowed: false, reason: "daily_limit", message: `Daily limit reached (${limits.dailyGenerations}/day)`, limit: limits.dailyGenerations, used: dailyCount };
  }
  if (record.last_generation_at) {
    const elapsed = (Date.now() - new Date(record.last_generation_at).getTime()) / 1e3;
    if (elapsed < limits.cooldownSeconds) {
      return { allowed: false, reason: "cooldown", message: `Wait ${Math.ceil(limits.cooldownSeconds - elapsed)}s`, waitSeconds: Math.ceil(limits.cooldownSeconds - elapsed) };
    }
  }
  return { allowed: true, remaining: limits.dailyGenerations - dailyCount - 1, limit: limits.dailyGenerations, tier: hasPaid ? "paid" : "free" };
}
__name(checkRateLimit, "checkRateLimit");
async function recordGeneration(env, userId) {
  const today = (/* @__PURE__ */ new Date()).toISOString().slice(0, 10);
  const rows = await supabase(env, "GET", "rate_limits", { filter: `user_id=eq.${userId}` });
  if (rows?.[0]) {
    const newCount = (rows[0].daily_date === today ? rows[0].daily_count : 0) + 1;
    await supabase(env, "PATCH", "rate_limits", {
      filter: `user_id=eq.${userId}`,
      body: { daily_count: newCount, daily_date: today, last_generation_at: (/* @__PURE__ */ new Date()).toISOString() }
    });
  } else {
    await supabase(env, "POST", "rate_limits", {
      body: { user_id: userId, daily_count: 1, daily_date: today, last_generation_at: (/* @__PURE__ */ new Date()).toISOString() },
      upsert: true
    });
  }
}
__name(recordGeneration, "recordGeneration");
async function handleAuth(request, env) {
  const { externalId, email, firebaseUid, fcmToken, platform, displayName, avatarUrl } = await request.json();
  if (!externalId) return json({ error: "externalId required" }, 400);
  let existing = await getUser(env, externalId);
  if (!existing && email) {
    const emailUser = await getUserByEmail(env, email);
    if (emailUser) {
      await supabase(env, "PATCH", "app_users", {
        filter: `id=eq.${emailUser.id}`,
        body: {
          id: externalId,
          firebase_uid: firebaseUid || void 0,
          fcm_token: fcmToken || void 0,
          platform: platform || void 0,
          display_name: displayName || emailUser.display_name,
          avatar_url: avatarUrl || emailUser.avatar_url
        }
      });
      existing = { ...emailUser, id: externalId };
    }
  }
  if (existing) {
    await upsertUser(env, {
      id: externalId,
      email: email || void 0,
      firebase_uid: firebaseUid || void 0,
      fcm_token: fcmToken || void 0,
      platform: platform || void 0,
      display_name: displayName || void 0,
      avatar_url: avatarUrl || void 0
    });
  } else {
    await upsertUser(env, {
      id: externalId,
      email: email || void 0,
      firebase_uid: firebaseUid || void 0,
      fcm_token: fcmToken || void 0,
      platform: platform || void 0,
      display_name: displayName || void 0,
      avatar_url: avatarUrl || void 0,
      credits: FREE_CREDITS
    });
  }
  return json({ ok: true, userId: externalId, credits: existing?.credits ?? FREE_CREDITS });
}
__name(handleAuth, "handleAuth");
async function handleCreditsGet(request, env) {
  const { userId, email } = await request.json();
  if (!userId) return json({ error: "userId required" }, 400);
  let user = await getUser(env, userId);
  if (!user && email) {
    user = await getUserByEmail(env, email);
    if (user && user.id !== userId) {
      await supabase(env, "PATCH", "app_users", {
        filter: `id=eq.${user.id}`,
        body: { id: userId }
      });
      user.id = userId;
    }
  }
  if (!user) {
    await upsertUser(env, { id: userId, email: email || void 0, credits: FREE_CREDITS });
    return json({ credits: FREE_CREDITS, isSubscribed: false });
  }
  if (user.credits == null) {
    await upsertUser(env, { id: userId, credits: FREE_CREDITS });
    user.credits = FREE_CREDITS;
  }
  const rateInfo = await checkRateLimit(env, userId);
  return json({
    credits: user.is_subscribed ? -1 : user.credits,
    isSubscribed: user.is_subscribed || false,
    rateLimit: rateInfo
  });
}
__name(handleCreditsGet, "handleCreditsGet");
async function handleCreditsAdd(request, env) {
  const { userId, productId, amount } = await request.json();
  if (!userId) return json({ error: "userId required" }, 400);
  let creditsToAdd = amount;
  if (!creditsToAdd && productId) creditsToAdd = IAP_PRODUCTS[productId];
  if (!creditsToAdd) return json({ error: "productId or amount required" }, 400);
  let user = await getUser(env, userId);
  const currentCredits = user?.credits || 0;
  const newCredits = currentCredits + creditsToAdd;
  await upsertUser(env, { id: userId, credits: newCredits });
  return json({ credits: newCredits, added: creditsToAdd });
}
__name(handleCreditsAdd, "handleCreditsAdd");
async function handleCreditsCheck(request, env) {
  const { userId, modelId, duration = 5 } = await request.json();
  if (!userId) return json({ error: "userId required" }, 400);
  const user = await getUser(env, userId);
  if (!user) return json({ allowed: true, credits: FREE_CREDITS, cost: 0 });
  if (user.is_subscribed) return json({ allowed: true, credits: -1, cost: 0, isSubscribed: true });
  const cost = calculateCost(modelId || "bytedance/seedance-1-lite", duration);
  return json({ allowed: (user.credits || 0) >= cost, credits: user.credits || 0, cost });
}
__name(handleCreditsCheck, "handleCreditsCheck");
async function handleCreditsDeduct(request, env) {
  const { userId, amount, modelId, duration = 5 } = await request.json();
  if (!userId) return json({ error: "userId required" }, 400);
  const cost = amount || calculateCost(modelId || "bytedance/seedance-1-lite", duration);
  const user = await getUser(env, userId);
  if (user?.is_subscribed) return json({ credits: -1, isSubscribed: true, deducted: 0 });
  if (!user || (user.credits || 0) < cost) return json({ error: "Insufficient credits", credits: user?.credits || 0, cost }, 402);
  const newCredits = (user.credits || 0) - cost;
  await supabase(env, "PATCH", "app_users", {
    filter: `id=eq.${userId}`,
    body: { credits: newCredits }
  });
  return json({ credits: newCredits, deducted: cost });
}
__name(handleCreditsDeduct, "handleCreditsDeduct");
async function handleCreateGenerate(request, env) {
  const { modelId, prompt, imageUrl, duration = 5, userId } = await request.json();
  if (!prompt) return json({ error: "prompt is required" }, 400);
  if (userId) {
    const rateCheck = await checkRateLimit(env, userId);
    if (!rateCheck.allowed) return json(rateCheck, 429);
  }
  if (userId) {
    const user = await getUser(env, userId);
    if (user && !user.is_subscribed) {
      const cost = calculateCost(modelId || "bytedance/seedance-1-lite", duration);
      if ((user.credits || 0) < cost) {
        return json({ error: "Insufficient credits", credits: user.credits || 0, cost }, 402);
      }
      await supabase(env, "PATCH", "app_users", {
        filter: `id=eq.${userId}`,
        body: { credits: (user.credits || 0) - cost }
      });
    }
  }
  const hasImage = !!imageUrl;
  let selectedModel = modelId;
  let input;
  let falModelId;
  if (hasImage) {
    if (!selectedModel || !MODEL_CONFIGS[selectedModel]?.i2v) selectedModel = "kwaivgi/kling-v2.1";
    const config = MODEL_CONFIGS[selectedModel];
    input = config.i2v(prompt, imageUrl, duration);
    falModelId = config.fal;
  } else {
    if (!selectedModel || !MODEL_CONFIGS[selectedModel]?.t2v) selectedModel = "bytedance/seedance-1-lite";
    const config = MODEL_CONFIGS[selectedModel];
    input = config.t2v(prompt, duration);
    falModelId = config.fal;
  }
  const falResponse = await falSubmit(env, falModelId, input);
  if (falResponse.detail || falResponse.error) {
    return json({ error: falResponse.detail || falResponse.error }, 500);
  }
  const id = crypto.randomUUID();
  await supabase(env, "POST", "ai_generations", {
    body: {
      id,
      user_id: userId || null,
      model_id: selectedModel,
      fal_model_id: falModelId,
      fal_request_id: falResponse.request_id,
      mode: hasImage ? "image-to-video" : "text-to-video",
      prompt,
      image_url: imageUrl || null,
      duration,
      status: "processing"
    },
    upsert: true
  });
  if (userId) await recordGeneration(env, userId);
  return json({ success: true, id, mode: hasImage ? "image-to-video" : "text-to-video", model: selectedModel, status: "processing" });
}
__name(handleCreateGenerate, "handleCreateGenerate");
async function handleCreateStatus(id, env) {
  const rows = await supabase(env, "GET", "ai_generations", {
    filter: `id=eq.${id}`,
    select: "*"
  });
  if (!rows?.length) return json({ error: "Not found" }, 404);
  const gen = rows[0];
  if (gen.status !== "succeeded" && gen.status !== "failed") {
    const status = await falStatus(env, gen.fal_model_id, gen.fal_request_id);
    if (status.status === "COMPLETED") {
      const result = await falResult(env, gen.fal_model_id, gen.fal_request_id);
      const outputUrl = result?.video?.url || result?.output?.url || null;
      await supabase(env, "PATCH", "ai_generations", {
        filter: `id=eq.${id}`,
        body: { status: "succeeded", output_url: outputUrl, completed_at: (/* @__PURE__ */ new Date()).toISOString() }
      });
      gen.status = "succeeded";
      gen.output_url = outputUrl;
    } else if (status.status === "FAILED") {
      await supabase(env, "PATCH", "ai_generations", {
        filter: `id=eq.${id}`,
        body: { status: "failed", error: status.error || "Generation failed", completed_at: (/* @__PURE__ */ new Date()).toISOString() }
      });
      gen.status = "failed";
      gen.error = status.error;
    }
  }
  return json({
    id: gen.id,
    status: gen.status,
    mode: gen.mode,
    model: gen.model_id,
    prompt: gen.prompt,
    outputUrl: gen.output_url,
    error: gen.error,
    duration: gen.duration,
    createdAt: gen.created_at,
    completedAt: gen.completed_at
  });
}
__name(handleCreateStatus, "handleCreateStatus");
function json(data, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { "Content-Type": "application/json", "Access-Control-Allow-Origin": "*" }
  });
}
__name(json, "json");
var src_default = {
  async fetch(request, env) {
    const url = new URL(request.url);
    const path = url.pathname;
    if (request.method === "OPTIONS") {
      return new Response(null, {
        headers: {
          "Access-Control-Allow-Origin": "*",
          "Access-Control-Allow-Methods": "GET, POST, PATCH, DELETE, OPTIONS",
          "Access-Control-Allow-Headers": "Content-Type, Authorization"
        }
      });
    }
    try {
      if (path === "/health") return json({ status: "ok", time: (/* @__PURE__ */ new Date()).toISOString() });
      if (path === "/api/auth/token" && request.method === "POST") return handleAuth(request, env);
      if (path === "/api/credits/get" && request.method === "POST") return handleCreditsGet(request, env);
      if (path === "/api/credits/add" && request.method === "POST") return handleCreditsAdd(request, env);
      if (path === "/api/credits/check" && request.method === "POST") return handleCreditsCheck(request, env);
      if (path === "/api/credits/deduct" && request.method === "POST") return handleCreditsDeduct(request, env);
      if (path === "/api/create/generate" && request.method === "POST") return handleCreateGenerate(request, env);
      if (path.startsWith("/api/create/status/") && request.method === "GET") {
        const id = path.split("/").pop();
        return handleCreateStatus(id, env);
      }
      return json({ error: "Not found" }, 404);
    } catch (err) {
      console.error("Worker error:", err);
      return json({ error: err.message }, 500);
    }
  }
};

// ../../../../.npm/_npx/32026684e21afda6/node_modules/wrangler/templates/middleware/middleware-ensure-req-body-drained.ts
var drainBody = /* @__PURE__ */ __name(async (request, env, _ctx, middlewareCtx) => {
  try {
    return await middlewareCtx.next(request, env);
  } finally {
    try {
      if (request.body !== null && !request.bodyUsed) {
        const reader = request.body.getReader();
        while (!(await reader.read()).done) {
        }
      }
    } catch (e) {
      console.error("Failed to drain the unused request body.", e);
    }
  }
}, "drainBody");
var middleware_ensure_req_body_drained_default = drainBody;

// ../../../../.npm/_npx/32026684e21afda6/node_modules/wrangler/templates/middleware/middleware-miniflare3-json-error.ts
function reduceError(e) {
  return {
    name: e?.name,
    message: e?.message ?? String(e),
    stack: e?.stack,
    cause: e?.cause === void 0 ? void 0 : reduceError(e.cause)
  };
}
__name(reduceError, "reduceError");
var jsonError = /* @__PURE__ */ __name(async (request, env, _ctx, middlewareCtx) => {
  try {
    return await middlewareCtx.next(request, env);
  } catch (e) {
    const error = reduceError(e);
    return Response.json(error, {
      status: 500,
      headers: { "MF-Experimental-Error-Stack": "true" }
    });
  }
}, "jsonError");
var middleware_miniflare3_json_error_default = jsonError;

// .wrangler/tmp/bundle-hvx9Ij/middleware-insertion-facade.js
var __INTERNAL_WRANGLER_MIDDLEWARE__ = [
  middleware_ensure_req_body_drained_default,
  middleware_miniflare3_json_error_default
];
var middleware_insertion_facade_default = src_default;

// ../../../../.npm/_npx/32026684e21afda6/node_modules/wrangler/templates/middleware/common.ts
var __facade_middleware__ = [];
function __facade_register__(...args) {
  __facade_middleware__.push(...args.flat());
}
__name(__facade_register__, "__facade_register__");
function __facade_invokeChain__(request, env, ctx, dispatch, middlewareChain) {
  const [head, ...tail] = middlewareChain;
  const middlewareCtx = {
    dispatch,
    next(newRequest, newEnv) {
      return __facade_invokeChain__(newRequest, newEnv, ctx, dispatch, tail);
    }
  };
  return head(request, env, ctx, middlewareCtx);
}
__name(__facade_invokeChain__, "__facade_invokeChain__");
function __facade_invoke__(request, env, ctx, dispatch, finalMiddleware) {
  return __facade_invokeChain__(request, env, ctx, dispatch, [
    ...__facade_middleware__,
    finalMiddleware
  ]);
}
__name(__facade_invoke__, "__facade_invoke__");

// .wrangler/tmp/bundle-hvx9Ij/middleware-loader.entry.ts
var __Facade_ScheduledController__ = class ___Facade_ScheduledController__ {
  constructor(scheduledTime, cron, noRetry) {
    this.scheduledTime = scheduledTime;
    this.cron = cron;
    this.#noRetry = noRetry;
  }
  static {
    __name(this, "__Facade_ScheduledController__");
  }
  #noRetry;
  noRetry() {
    if (!(this instanceof ___Facade_ScheduledController__)) {
      throw new TypeError("Illegal invocation");
    }
    this.#noRetry();
  }
};
function wrapExportedHandler(worker) {
  if (__INTERNAL_WRANGLER_MIDDLEWARE__ === void 0 || __INTERNAL_WRANGLER_MIDDLEWARE__.length === 0) {
    return worker;
  }
  for (const middleware of __INTERNAL_WRANGLER_MIDDLEWARE__) {
    __facade_register__(middleware);
  }
  const fetchDispatcher = /* @__PURE__ */ __name(function(request, env, ctx) {
    if (worker.fetch === void 0) {
      throw new Error("Handler does not export a fetch() function.");
    }
    return worker.fetch(request, env, ctx);
  }, "fetchDispatcher");
  return {
    ...worker,
    fetch(request, env, ctx) {
      const dispatcher = /* @__PURE__ */ __name(function(type, init) {
        if (type === "scheduled" && worker.scheduled !== void 0) {
          const controller = new __Facade_ScheduledController__(
            Date.now(),
            init.cron ?? "",
            () => {
            }
          );
          return worker.scheduled(controller, env, ctx);
        }
      }, "dispatcher");
      return __facade_invoke__(request, env, ctx, dispatcher, fetchDispatcher);
    }
  };
}
__name(wrapExportedHandler, "wrapExportedHandler");
function wrapWorkerEntrypoint(klass) {
  if (__INTERNAL_WRANGLER_MIDDLEWARE__ === void 0 || __INTERNAL_WRANGLER_MIDDLEWARE__.length === 0) {
    return klass;
  }
  for (const middleware of __INTERNAL_WRANGLER_MIDDLEWARE__) {
    __facade_register__(middleware);
  }
  return class extends klass {
    #fetchDispatcher = /* @__PURE__ */ __name((request, env, ctx) => {
      this.env = env;
      this.ctx = ctx;
      if (super.fetch === void 0) {
        throw new Error("Entrypoint class does not define a fetch() function.");
      }
      return super.fetch(request);
    }, "#fetchDispatcher");
    #dispatcher = /* @__PURE__ */ __name((type, init) => {
      if (type === "scheduled" && super.scheduled !== void 0) {
        const controller = new __Facade_ScheduledController__(
          Date.now(),
          init.cron ?? "",
          () => {
          }
        );
        return super.scheduled(controller);
      }
    }, "#dispatcher");
    fetch(request) {
      return __facade_invoke__(
        request,
        this.env,
        this.ctx,
        this.#dispatcher,
        this.#fetchDispatcher
      );
    }
  };
}
__name(wrapWorkerEntrypoint, "wrapWorkerEntrypoint");
var WRAPPED_ENTRY;
if (typeof middleware_insertion_facade_default === "object") {
  WRAPPED_ENTRY = wrapExportedHandler(middleware_insertion_facade_default);
} else if (typeof middleware_insertion_facade_default === "function") {
  WRAPPED_ENTRY = wrapWorkerEntrypoint(middleware_insertion_facade_default);
}
var middleware_loader_entry_default = WRAPPED_ENTRY;
export {
  __INTERNAL_WRANGLER_MIDDLEWARE__,
  middleware_loader_entry_default as default
};
//# sourceMappingURL=index.js.map
