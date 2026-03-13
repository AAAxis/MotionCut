/**
 * Stock Footage Service — fetches video clips from Pexels
 */
const fetch = require('node-fetch');
const fs = require('fs');
const path = require('path');

const PEXELS_KEY = process.env.PEXELS_API_KEY;

async function searchVideos(query, count = 3) {
  const res = await fetch(
    `https://api.pexels.com/videos/search?query=${encodeURIComponent(query)}&per_page=${count}&size=medium&orientation=landscape`,
    { headers: { Authorization: PEXELS_KEY } }
  );

  if (!res.ok) throw new Error(`Pexels error: ${res.status}`);

  const data = await res.json();
  return (data.videos || []).map(v => {
    // Prefer HD (1280x720) or SD file
    const file = v.video_files
      .filter(f => f.quality === 'hd' || f.quality === 'sd')
      .sort((a, b) => (b.width || 0) - (a.width || 0))[0]
      || v.video_files[0];

    return {
      id: v.id,
      url: file.link,
      width: file.width,
      height: file.height,
      duration: v.duration,
      image: v.image, // preview thumbnail
    };
  });
}

async function downloadVideo(url, outputPath) {
  const res = await fetch(url);
  if (!res.ok) throw new Error(`Download failed: ${res.status}`);

  const dir = path.dirname(outputPath);
  if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });

  const fileStream = fs.createWriteStream(outputPath);
  return new Promise((resolve, reject) => {
    res.body.pipe(fileStream);
    res.body.on('error', reject);
    fileStream.on('finish', resolve);
  });
}

async function fetchFootageForScenes(scenes) {
  const results = [];

  for (const scene of scenes) {
    try {
      const videos = await searchVideos(scene.searchQuery, 2);
      if (videos.length > 0) {
        // Pick random from top results
        const pick = videos[Math.floor(Math.random() * videos.length)];
        results.push({ ...scene, footage: pick });
      } else {
        // Fallback: search with simpler query
        const fallback = await searchVideos(scene.searchQuery.split(' ').slice(0, 2).join(' '), 2);
        results.push({ ...scene, footage: fallback[0] || null });
      }
    } catch (err) {
      console.error(`Footage search failed for "${scene.searchQuery}":`, err.message);
      results.push({ ...scene, footage: null });
    }

    // Rate limit: Pexels allows 200 req/hr
    await new Promise(r => setTimeout(r, 300));
  }

  return results;
}

module.exports = { searchVideos, downloadVideo, fetchFootageForScenes };
