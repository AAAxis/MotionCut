/**
 * AI Script Generator — turns scraped data + prompt into a video script
 * Uses OpenRouter (Claude/GPT) for generation
 */
const fetch = require('node-fetch');

const OPENROUTER_KEY = process.env.OPENROUTER_API_KEY;
const MODEL = 'anthropic/claude-3.5-sonnet';

async function generateScript(scrapedData, userPrompt, options = {}) {
  const { scenes = 5, duration = 30, style = 'modern' } = options;

  const systemPrompt = `You are a professional video ad script writer. You create compelling, short-form video ad scripts from product/service information.

Output ONLY valid JSON (no markdown, no code blocks). The JSON must match this schema:
{
  "title": "Video title",
  "totalDuration": ${duration},
  "style": "${style}",
  "scenes": [
    {
      "sceneNumber": 1,
      "duration": 5,
      "visualDescription": "What to show visually (for stock footage search)",
      "textOverlay": "Bold text shown on screen (max 8 words)",
      "voiceover": "What the narrator says",
      "searchQuery": "Pexels search query for background footage",
      "transition": "fade|slide|zoom|cut"
    }
  ],
  "music": {
    "mood": "upbeat|corporate|dramatic|inspiring|chill",
    "tempo": "fast|medium|slow"
  },
  "cta": {
    "text": "Call to action text",
    "url": "original URL"
  }
}

Rules:
- Each scene is 4-8 seconds
- Text overlays are SHORT and punchy (max 8 words)
- Voiceover is natural and conversational
- Search queries should find relevant stock footage on Pexels
- First scene is a hook (grab attention in 2-3 seconds)
- Last scene is always the CTA
- Total scenes: ${scenes}
- Total duration: ~${duration} seconds`;

  const userMessage = `Create a video ad script for this product/service:

**URL:** ${scrapedData.url}
**Title:** ${scrapedData.title}
**Description:** ${scrapedData.description}
**Key Features:**
${scrapedData.features.slice(0, 8).map(f => `- ${f}`).join('\n')}
**Sections:**
${scrapedData.sections.slice(0, 5).map(s => `- ${s.heading}: ${s.text}`).join('\n')}
**Prices:** ${scrapedData.prices.join(', ') || 'Not specified'}

**User's direction:** ${userPrompt || 'Create a compelling ad that highlights the main value proposition'}

Generate a ${scenes}-scene video ad script (~${duration}s total).`;

  const res = await fetch('https://openrouter.ai/api/v1/chat/completions', {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${OPENROUTER_KEY}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      model: MODEL,
      messages: [
        { role: 'system', content: systemPrompt },
        { role: 'user', content: userMessage },
      ],
      temperature: 0.7,
      max_tokens: 2000,
    }),
  });

  if (!res.ok) {
    const err = await res.text();
    throw new Error(`OpenRouter error: ${res.status} ${err}`);
  }

  const data = await res.json();
  const content = data.choices[0].message.content.trim();

  // Parse JSON (handle markdown code blocks just in case)
  const jsonStr = content.replace(/^```json?\n?/m, '').replace(/\n?```$/m, '').trim();
  const script = JSON.parse(jsonStr);

  return script;
}

module.exports = { generateScript };
