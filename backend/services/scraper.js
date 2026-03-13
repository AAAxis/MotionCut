/**
 * URL Scraper — extracts product/landing page info for video generation
 */
const cheerio = require('cheerio');
const fetch = require('node-fetch');

async function scrapeUrl(url) {
  const res = await fetch(url, {
    headers: {
      'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36',
      'Accept': 'text/html,application/xhtml+xml',
    },
    timeout: 15000,
  });

  if (!res.ok) throw new Error(`Failed to fetch URL: ${res.status}`);

  const html = await res.text();
  const $ = cheerio.load(html);

  // Remove scripts, styles, nav, footer
  $('script, style, nav, footer, header, iframe, noscript').remove();

  // Extract metadata
  const title = $('meta[property="og:title"]').attr('content')
    || $('title').text().trim()
    || $('h1').first().text().trim();

  const description = $('meta[property="og:description"]').attr('content')
    || $('meta[name="description"]').attr('content')
    || '';

  const ogImage = $('meta[property="og:image"]').attr('content') || '';

  // Extract all images
  const images = [];
  $('img').each((_, el) => {
    const src = $(el).attr('src') || $(el).attr('data-src');
    if (src && !src.includes('icon') && !src.includes('logo') && !src.includes('avatar')) {
      const fullUrl = src.startsWith('http') ? src : new URL(src, url).href;
      images.push(fullUrl);
    }
  });

  // Extract prices
  const pricePatterns = /\$[\d,.]+|\€[\d,.]+|£[\d,.]+|USD\s*[\d,.]+/g;
  const bodyText = $('body').text();
  const prices = [...new Set((bodyText.match(pricePatterns) || []).slice(0, 5))];

  // Extract key text blocks (headings + nearby paragraphs)
  const sections = [];
  $('h1, h2, h3').each((_, el) => {
    const heading = $(el).text().trim();
    const nextP = $(el).nextAll('p').first().text().trim();
    if (heading && heading.length < 200) {
      sections.push({ heading, text: nextP.slice(0, 300) });
    }
  });

  // Extract features/bullet points
  const features = [];
  $('li').each((_, el) => {
    const text = $(el).text().trim();
    if (text.length > 10 && text.length < 200) {
      features.push(text);
    }
  });

  return {
    url,
    title: title.slice(0, 200),
    description: description.slice(0, 500),
    ogImage,
    images: images.slice(0, 10),
    prices,
    sections: sections.slice(0, 10),
    features: features.slice(0, 15),
    domain: new URL(url).hostname,
  };
}

module.exports = { scrapeUrl };
