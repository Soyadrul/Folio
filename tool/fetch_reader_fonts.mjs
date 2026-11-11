#!/usr/bin/env node
import { mkdir, writeFile } from 'node:fs/promises';
import { resolve } from 'node:path';

const outputDir = resolve(
  new URL('.', import.meta.url).pathname,
  '..',
  'assets/reader/fonts'
);

const families = [
  { api: 'Merriweather', slug: 'merriweather', variable: true, bold: false },
  { api: 'Lora', slug: 'lora', variable: true, bold: false },
  { api: 'Playfair Display', slug: 'playfair-display', variable: true, bold: false },
  { api: 'Crimson Text', slug: 'crimson-text', variable: false, bold: true },
  { api: 'EB Garamond', slug: 'eb-garamond', variable: true, bold: false },
  { api: 'PT Serif', slug: 'pt-serif', variable: false, bold: true },
  { api: 'Source Serif 4', slug: 'source-serif-4', variable: true, bold: false },
  { api: 'Libre Baskerville', slug: 'libre-baskerville', variable: true, bold: false },
  { api: 'Roboto', slug: 'roboto', variable: true, bold: false },
  { api: 'Open Sans', slug: 'open-sans', variable: true, bold: false },
  { api: 'Lato', slug: 'lato', variable: false, bold: true },
  { api: 'Noto Sans', slug: 'noto-sans', variable: true, bold: false },
];

const userAgent =
  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 ' +
  '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';

function axesFor(family) {
  if (family.variable) return 'ital,wght@0,400..700;1,400';
  if (family.bold) return 'ital,wght@0,400;0,700;1,400';
  return 'ital,wght@0,400;1,400';
}

async function fetchCss(family) {
  const url =
    `https://fonts.googleapis.com/css2?family=${encodeURIComponent(family.api)}` +
    `:${axesFor(family)}&display=swap`;
  const response = await fetch(url, { headers: { 'User-Agent': userAgent } });
  if (!response.ok) {
    throw new Error(`${family.api}: HTTP ${response.status}`);
  }
  return response.text();
}

function latinExtFaces(css) {
  const faces = new Map();
  for (const chunk of css.split('/*').slice(1)) {
    const close = chunk.indexOf('*/');
    if (close < 0) continue;
    if (chunk.slice(0, close).trim() !== 'latin-ext') continue;
    const body = chunk.slice(close + 2);
    const style = /font-style:\s*([a-z]+)/i.exec(body)?.[1];
    const weight = /font-weight:\s*([0-9]+)/.exec(body)?.[1];
    const url = /url\((https:[^)]+\.woff2)\)/.exec(body)?.[1];
    if (style && weight && url) faces.set(`${style}-${weight}`, url);
  }
  return faces;
}

await mkdir(outputDir, { recursive: true });

for (const family of families) {
  const faces = latinExtFaces(await fetchCss(family));
  const wanted = [
    { style: 'normal', weight: '400' },
    ...(family.bold ? [{ style: 'normal', weight: '700' }] : []),
    { style: 'italic', weight: '400' },
  ];
  for (const face of wanted) {
    const url = faces.get(`${face.style}-${face.weight}`);
    if (!url) {
      throw new Error(`${family.api}: missing latin-ext ${face.style} ${face.weight}`);
    }
    const name = `${family.slug}-${face.style}-${face.weight}-latin-ext.woff2`;
    const bytes = Buffer.from(await (await fetch(url)).arrayBuffer());
    await writeFile(resolve(outputDir, name), bytes);
    console.log(`${name}: ${bytes.length} bytes`);
  }
}
