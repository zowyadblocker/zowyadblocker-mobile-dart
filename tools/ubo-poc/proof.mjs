import assert from 'node:assert/strict';
import { performance } from 'node:perf_hooks';
import { writeFile } from 'node:fs/promises';
import { StaticNetFilteringEngine } from '@gorhill/ubo-core';

const before = process.memoryUsage();
const start = performance.now();
const engine = await StaticNetFilteringEngine.create();
await engine.useLists([{name: 'controlled-fixture', raw: [
  '||ads.example^',
  '@@||allowed.ads.example^',
  '||example.org/banner.js$script,third-party',
  '||important.example^$important',
  '@@||important.example^',
].join('\n')}]);
const compileMs = performance.now() - start;
const cases = [
  ['https://ads.example/a', 'https://site.example/', 'script', 1],
  ['https://allowed.ads.example/a', 'https://site.example/', 'script', 2],
  ['https://content.example/a', 'https://site.example/', 'script', 0],
  ['https://example.org/banner.js', 'https://site.example/', 'script', 1],
  ['https://example.org/banner.js', 'https://example.org/', 'script', 0],
  ['https://important.example/', 'https://site.example/', 'script', 1],
];
const results = [];
for (const [url, originURL, type, expected] of cases) {
  const actual = engine.matchRequest({url, originURL, type});
  assert.equal(actual, expected, url);
  results.push({url, originURL, type, actual, explanation: actual ? engine.toLogData() : null});
}
const serialized = await engine.serialize();
await engine.useLists([]);
await engine.deserialize(serialized);
assert.equal(engine.matchRequest({url: 'https://ads.example/x', originURL: 'https://site.example', type: 'script'}), 1);
const matchStart = performance.now();
for (let i = 0; i < 100000; i++) engine.matchRequest({url: 'https://ads.example/x', originURL: 'https://site.example', type: 'script'});
const report = {package: '@gorhill/ubo-core@0.1.30', runtime: process.version,
  platform: `${process.platform}/${process.arch}`, compileMs,
  match100kMs: performance.now() - matchStart,
  serializedBytes: Buffer.byteLength(serialized), before, after: process.memoryUsage(),
  results, limitation: 'Desktop Node proof only. No Android or QuickJS embedding/performance claim.'};
console.log(JSON.stringify(report, null, 2));
await writeFile(new URL('../../docs/ubo-proof-results.json', import.meta.url), JSON.stringify(report, null, 2) + '\n');
await StaticNetFilteringEngine.release();
