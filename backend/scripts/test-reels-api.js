#!/usr/bin/env node

const args = process.argv.slice(2);

function getArg(name, fallback) {
  const prefix = `--${name}=`;
  const direct = args.find(arg => arg.startsWith(prefix));
  if (direct) return direct.slice(prefix.length);

  const index = args.indexOf(`--${name}`);
  if (index >= 0 && args[index + 1]) return args[index + 1];

  return fallback;
}

function hasFlag(name) {
  return args.includes(`--${name}`);
}

const baseUrl = getArg('base-url', process.env.API_BASE_URL || 'http://api.holylabs.net');
const topic = getArg('topic', 'debug reel api');
const language = getArg('language', 'en');
const duration = Number(getArg('duration', '10'));
const timeoutMs = Number(getArg('timeout-ms', '120000'));
const skipGenerate = hasFlag('skip-generate');

function pretty(value) {
  return JSON.stringify(value, null, 2);
}

async function testHealth() {
  const url = `${baseUrl}/health`;
  console.log(`\n[health] GET ${url}`);

  const res = await fetch(url);
  const text = await res.text();

  console.log(`[health] status=${res.status}`);
  console.log(`[health] body=${text}`);
}

async function testPlanSSE() {
  const url = `${baseUrl}/api/reels/plan`;
  const body = {
    topic,
    language,
    duration,
  };

  console.log(`\n[plan] POST ${url}`);
  console.log(`[plan] request=${pretty(body)}`);

  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);

  let response;
  try {
    response = await fetch(url, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(body),
      signal: controller.signal,
    });
  } catch (error) {
    clearTimeout(timer);
    throw error;
  }

  console.log(`[plan] status=${response.status}`);
  console.log(`[plan] content-type=${response.headers.get('content-type') || ''}`);

  if (!response.ok) {
    clearTimeout(timer);
    const text = await response.text();
    console.log(`[plan] error-body=${text}`);
    return { ok: false, reason: `HTTP ${response.status}` };
  }

  let buffer = '';
  let lastProgress = null;
  let donePayload = null;
  let errorPayload = null;
  let eventCount = 0;

  const parseBlock = block => {
    const lines = block
      .split('\n')
      .map(line => line.trimEnd())
      .filter(Boolean);

    if (!lines.length) return;

    let event = 'message';
    const dataLines = [];

    for (const line of lines) {
      if (line.startsWith('event:')) {
        event = line.slice(6).trim();
      } else if (line.startsWith('data:')) {
        dataLines.push(line.slice(5).trim());
      }
    }

    const rawData = dataLines.join('\n');
    let parsed = rawData;
    try {
      parsed = JSON.parse(rawData);
    } catch {}

    eventCount += 1;
    console.log(`[plan] event #${eventCount}: ${event}`);
    console.log(pretty(parsed));

    if (event === 'progress') lastProgress = parsed;
    if (event === 'done') donePayload = parsed;
    if (event === 'error') errorPayload = parsed;
  };

  try {
    for await (const chunk of response.body) {
      buffer += chunk.toString('utf8').replace(/\r\n/g, '\n');

      while (buffer.includes('\n\n')) {
        const splitIndex = buffer.indexOf('\n\n');
        const block = buffer.slice(0, splitIndex);
        buffer = buffer.slice(splitIndex + 2);
        parseBlock(block);

        if (donePayload || errorPayload) {
          clearTimeout(timer);
          break;
        }
      }

      if (donePayload || errorPayload) break;
    }
  } catch (error) {
    clearTimeout(timer);

    if (error.name === 'AbortError') {
      console.log(`[plan] timed out after ${timeoutMs}ms`);
      return {
        ok: false,
        reason: 'timeout',
        lastProgress,
        eventCount,
      };
    }

    throw error;
  }

  clearTimeout(timer);

  if (donePayload) {
    const takesCount = Array.isArray(donePayload.takes) ? donePayload.takes.length : 0;
    console.log(`[plan] done: takes=${takesCount} musicUrl=${donePayload.musicUrl || 'null'}`);
    return {
      ok: true,
      donePayload,
      lastProgress,
      eventCount,
    };
  }

  if (errorPayload) {
    console.log(`[plan] stream error received`);
    return {
      ok: false,
      reason: 'stream-error',
      errorPayload,
      lastProgress,
      eventCount,
    };
  }

  console.log('[plan] stream ended without done/error');
  return {
    ok: false,
    reason: 'ended-without-terminal-event',
    lastProgress,
    eventCount,
  };
}

async function testGenerateJSON() {
  const url = `${baseUrl}/api/reels/generate`;
  const body = {
    topic,
    language,
    duration,
  };

  console.log(`\n[generate] POST ${url}`);
  console.log(`[generate] request=${pretty(body)}`);

  const res = await fetch(url, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  });

  const text = await res.text();
  console.log(`[generate] status=${res.status}`);
  console.log(`[generate] body=${text}`);
}

async function main() {
  console.log(`[config] baseUrl=${baseUrl}`);
  console.log(`[config] topic=${topic}`);
  console.log(`[config] language=${language}`);
  console.log(`[config] duration=${duration}`);
  console.log(`[config] timeoutMs=${timeoutMs}`);

  await testHealth();
  const planResult = await testPlanSSE();

  if (!skipGenerate) {
    await testGenerateJSON();
  }

  if (!planResult.ok) {
    process.exitCode = 1;
  }
}

main().catch(error => {
  console.error('\n[fatal]');
  console.error(error);
  process.exit(1);
});
