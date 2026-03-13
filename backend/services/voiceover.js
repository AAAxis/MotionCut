/**
 * Voiceover Service — generates speech from text via ElevenLabs
 */
const fetch = require('node-fetch');
const fs = require('fs');
const path = require('path');

const ELEVENLABS_KEY = process.env.ELEVENLABS_API_KEY;

// Good default voices for ads
const VOICES = {
  male_professional: '29vD33N1CtxCmqQRPOHJ',    // Drew
  female_professional: 'EXAVITQu4vr4xnSDxMaL',  // Sarah
  male_casual: 'TX3LPaxmHKxFdv7VOQHJ',          // Liam
  female_casual: 'XB0fDUnXU5powFXDhCwa',         // Charlotte
  narrator: 'pNInz6obpgDQGcFmaJgB',              // Adam
};

const DEFAULT_VOICE = VOICES.male_professional;

/**
 * Generate voiceover audio for a single text
 * Returns path to saved mp3 file
 */
async function generateVoiceover(text, outputPath, options = {}) {
  const voiceId = options.voiceId || DEFAULT_VOICE;
  const model = options.model || 'eleven_multilingual_v2';

  const res = await fetch(`https://api.elevenlabs.io/v1/text-to-speech/${voiceId}`, {
    method: 'POST',
    headers: {
      'xi-api-key': ELEVENLABS_KEY,
      'Content-Type': 'application/json',
      'Accept': 'audio/mpeg',
    },
    body: JSON.stringify({
      text,
      model_id: model,
      voice_settings: {
        stability: 0.6,
        similarity_boost: 0.75,
        style: 0.3,
        use_speaker_boost: true,
      },
    }),
  });

  if (!res.ok) {
    const err = await res.text();
    throw new Error(`ElevenLabs error: ${res.status} ${err}`);
  }

  const dir = path.dirname(outputPath);
  if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });

  const fileStream = fs.createWriteStream(outputPath);
  return new Promise((resolve, reject) => {
    res.body.pipe(fileStream);
    res.body.on('error', reject);
    fileStream.on('finish', () => resolve(outputPath));
  });
}

/**
 * Generate voiceovers for all scenes
 * Returns array of audio file paths
 */
async function generateSceneVoiceovers(scenes, jobDir, options = {}) {
  const audioPaths = [];

  for (let i = 0; i < scenes.length; i++) {
    const scene = scenes[i];
    if (!scene.voiceover) {
      audioPaths.push(null);
      continue;
    }

    const audioPath = path.join(jobDir, `voice_${i}.mp3`);
    console.log(`Voice ${i + 1}: "${scene.voiceover.slice(0, 50)}..."`);

    try {
      await generateVoiceover(scene.voiceover, audioPath, options);
      audioPaths.push(audioPath);
    } catch (err) {
      console.error(`Voice ${i + 1} failed:`, err.message);
      audioPaths.push(null);
    }

    // Small delay to respect rate limits
    await new Promise(r => setTimeout(r, 200));
  }

  return audioPaths;
}

/**
 * List available voices from ElevenLabs
 */
async function listVoices() {
  const res = await fetch('https://api.elevenlabs.io/v1/voices', {
    headers: { 'xi-api-key': ELEVENLABS_KEY },
  });
  if (!res.ok) throw new Error(`ElevenLabs error: ${res.status}`);
  const data = await res.json();
  return data.voices.map(v => ({
    id: v.voice_id,
    name: v.name,
    category: v.category,
    labels: v.labels,
  }));
}

module.exports = { generateVoiceover, generateSceneVoiceovers, listVoices, VOICES };
