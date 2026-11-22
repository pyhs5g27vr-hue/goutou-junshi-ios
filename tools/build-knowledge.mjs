// 把 SKILL.md + references/*.md 打包成 App 内嵌的 knowledge.json
// 用法: node tools/build-knowledge.mjs
import { readFileSync, writeFileSync, readdirSync, statSync } from 'node:fs';
import { join, relative, basename } from 'node:path';

const RES = new URL('../Resources/', import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, '$1');
const OUT = join(RES, '..', 'Sources', 'knowledge.json');

const skill = readFileSync(join(RES, 'SKILL.md'), 'utf8');

const walk = (dir) =>
  readdirSync(dir).flatMap((name) => {
    const p = join(dir, name);
    return statSync(p).isDirectory() ? walk(p) : [p];
  });

const docFiles = walk(join(RES, 'references')).filter((f) => f.endsWith('.md'));

const stripPrefix = (s) => s.replace(/^\d+[-_]/, '').replace(/\.md$/, '');

// 关键词：短语级，不做任意滑窗，避免产生「据分级与」这种噪声词
const DROP = new Set([
  '指南', '技巧', '实用', '通用', '一份', '当前', '问题', '对应', '总论', '适配',
  'the', 'and', 'for', 'with', 'from', 'md', '一', '二', '三',
]);

function phraseKeys(text) {
  // 先按标点/空白切成大块，再在块内按顿号、冒号、与、的 细分
  const chunks = text
    .replace(/[，。、；：,;:（）()【】\[\]「」《》""'']/g, '\u0001')
    .split('\u0001');
  const out = new Set();
  for (const raw of chunks) {
    const c = raw.trim();
    if (c.length < 2) continue;
    if (DROP.has(c)) continue;
    out.add(c);
    // 「A与B」「A和B」拆开
    for (const p of c.split(/[与和及]/)) {
      const q = p.trim();
      if (q.length >= 2 && !DROP.has(q)) out.add(q);
    }
  }
  return [...out];
}

const docs = docFiles.map((f) => {
  const rel = relative(RES, f).split('\\').join('/');
  const raw = readFileSync(f, 'utf8');
  const stem = stripPrefix(basename(f));
  const cat = rel.includes('/knowledge/') ? 'knowledge' : 'practical';

  const keys = new Set();
  // 1) 文件名整段与拆分片段，权重最高（运行时按命中长度加权）
  keys.add(stem);
  for (const k of phraseKeys(stem)) keys.add(k);
  // 2) 文档一级/二级标题
  for (const m of raw.matchAll(/^#{1,2}\s+(.+)$/gm)) {
    const h = m[1].replace(/[#*`]/g, '').trim();
    if (h.length >= 2 && h.length <= 24) keys.add(h);
  }

  // 3) 正文里出现频次最高的 2–4 字中文短语（只用来兜底，权重低）
  const freq = new Map();
  for (const seg of raw.slice(0, 6000).split(/[^\u4e00-\u9fa5]+/)) {
    for (let n = 2; n <= 4; n++) {
      for (let i = 0; i + n <= seg.length; i++) {
        const k = seg.slice(i, i + n);
        if (DROP.has(k)) continue;
        freq.set(k, (freq.get(k) || 0) + 1);
      }
    }
  }
  const bodyKeys = [...freq.entries()]
    .filter(([k, v]) => v >= 4 && k.length >= 3)
    .sort((a, b) => b[1] - a[1])
    .slice(0, 30)
    .map(([k]) => k);
  for (const k of bodyKeys) keys.add(k);

  return {
    id: rel,
    path: rel,
    title: stem,
    cat,
    words: raw.length,
    keys: [...keys],
    text: raw,
  };
});

const payload = {
  version: 4,
  builtAt: new Date().toISOString(),
  skill,
  docs,
};

writeFileSync(OUT, JSON.stringify(payload));
const bytes = statSync(OUT).size;
console.log(`wrote ${OUT}`);
console.log(`docs=${docs.length} bytes=${(bytes / 1024).toFixed(1)}KB  avgKeys=${Math.round(docs.reduce((a, d) => a + d.keys.length, 0) / docs.length)}`);
for (const d of docs.slice(0, 2)) console.log(`  ${d.path}\n    keys=${d.keys.slice(0, 10).join(' | ')}`);
