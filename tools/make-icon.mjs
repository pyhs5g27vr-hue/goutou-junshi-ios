// 生成 1024x1024 AppIcon（纯 zlib + 手写 PNG，无第三方依赖）
//
// 形状用 5×5 超采样求覆盖度，避免隐函数边界上出现方块状伪影。
import { deflateSync } from 'node:zlib';
import { writeFileSync, mkdirSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');
const S = 1024;
const px = Buffer.alloc(S * S * 4);

// ---------- 数学工具 ----------
const clamp01 = (v) => (v < 0 ? 0 : v > 1 ? 1 : v);
const mix = (a, b, t) => a + (b - a) * t;

// 心形隐函数：(x²+y²-1)³ - x²y³ <= 0
function inHeart(x, y) {
  const a = x * x + y * y - 1;
  return a * a * a - x * x * y * y * y <= 0;
}

// 三段暖色渐变（左上橙 → 中粉 → 右下紫）
function backdrop(t) {
  t = clamp01(t);
  if (t < 0.5) {
    const k = t / 0.5;
    return [mix(255, 255, k), mix(152, 106, k), mix(96, 140, k)];
  }
  const k = (t - 0.5) / 0.5;
  return [mix(255, 174, k), mix(106, 108, k), mix(140, 248, k)];
}

// ---------- 绘制 ----------
const SCALE = 0.255;      // 心形占画布比例
const CX = 0.5;
const CY = 0.505;
const SUB = 5;            // 超采样格数
const SUBW = 1 / (SUB * SUB);

for (let py = 0; py < S; py++) {
  for (let pxx = 0; pxx < S; pxx++) {
    const u = pxx / S;
    const v = py / S;
    const t = clamp01(u * 0.55 + v * 0.45);
    let [r, g, b] = backdrop(t);

    // 顶部一层柔光，给纯渐变一点体积
    const glow = Math.max(0, 1 - Math.hypot(u - 0.28, v - 0.12) / 0.75);
    const gl = glow * glow * 22;
    r = Math.min(255, r + gl);
    g = Math.min(255, g + gl * 0.85);
    b = Math.min(255, b + gl * 0.55);

    // 心形覆盖度
    let hits = 0;
    for (let sy = 0; sy < SUB; sy++) {
      for (let sx = 0; sx < SUB; sx++) {
        const hx = ((pxx + (sx + 0.5) / SUB) / S - CX) / SCALE;
        const hy = -((py + (sy + 0.5) / SUB) / S - CY) / SCALE - 0.15;
        if (inHeart(hx, hy)) hits++;
      }
    }
    const cover = hits * SUBW;

    if (cover > 0) {
      // 心形内部：奶白 → 淡桃色，竖向渐变
      const k = clamp01((v - 0.24) / 0.55);
      const hr = mix(255, 255, k);
      const hg = mix(253, 232, k);
      const hb = mix(248, 220, k);
      r = mix(r, hr, cover);
      g = mix(g, hg, cover);
      b = mix(b, hb, cover);

      // 左上一块高光，让它看起来是立体的
      const lx = (u - 0.40) / 0.22;
      const ly = (v - 0.30) / 0.22;
      const spec = Math.max(0, 1 - Math.hypot(lx, ly));
      const sp = spec * spec * 26 * cover;
      r = Math.min(255, r + sp);
      g = Math.min(255, g + sp);
      b = Math.min(255, b + sp);
    }

    const i = (py * S + pxx) * 4;
    px[i] = Math.round(r);
    px[i + 1] = Math.round(g);
    px[i + 2] = Math.round(b);
    px[i + 3] = 255;
  }
}

// ---------- PNG 编码 ----------
const CRC_TABLE = (() => {
  const table = new Int32Array(256);
  for (let n = 0; n < 256; n++) {
    let c = n;
    for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
    table[n] = c;
  }
  return table;
})();

function crc32(buf) {
  let c = 0xffffffff;
  for (let i = 0; i < buf.length; i++) c = CRC_TABLE[(c ^ buf[i]) & 0xff] ^ (c >>> 8);
  return (c ^ 0xffffffff) >>> 0;
}

function chunk(type, data) {
  const len = Buffer.alloc(4);
  len.writeUInt32BE(data.length, 0);
  const body = Buffer.concat([Buffer.from(type, 'ascii'), data]);
  const crc = Buffer.alloc(4);
  crc.writeUInt32BE(crc32(body), 0);
  return Buffer.concat([len, body, crc]);
}

const ihdr = Buffer.alloc(13);
ihdr.writeUInt32BE(S, 0);
ihdr.writeUInt32BE(S, 4);
ihdr[8] = 8;  // bit depth
ihdr[9] = 6;  // RGBA
const raw = Buffer.alloc(S * (S * 4 + 1));
for (let y = 0; y < S; y++) {
  px.copy(raw, y * (S * 4 + 1) + 1, y * S * 4, (y + 1) * S * 4);
}

const png = Buffer.concat([
  Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
  chunk('IHDR', ihdr),
  chunk('IDAT', deflateSync(raw, { level: 9 })),
  chunk('IEND', Buffer.alloc(0)),
]);

// ---------- 写入 Xcode 资源 ----------
const outDir = join(ROOT, 'Sources', 'Assets.xcassets', 'AppIcon.appiconset');
mkdirSync(outDir, { recursive: true });
writeFileSync(join(outDir, 'icon-1024.png'), png);
writeFileSync(
  join(outDir, 'Contents.json'),
  JSON.stringify(
    {
      images: [{ filename: 'icon-1024.png', idiom: 'universal', platform: 'ios', size: '1024x1024' }],
      info: { author: 'xcode', version: 1 },
    },
    null,
    2
  ) + '\n'
);
writeFileSync(
  join(ROOT, 'Sources', 'Assets.xcassets', 'Contents.json'),
  JSON.stringify({ info: { author: 'xcode', version: 1 } }, null, 2) + '\n'
);

console.log(`icon ok: ${(png.length / 1024).toFixed(1)} KB`);
