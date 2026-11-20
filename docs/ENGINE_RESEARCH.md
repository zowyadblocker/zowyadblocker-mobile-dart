# Filtering engine research

Investigated 2026-11-20 against official sources and the pinned npm package.

## Official uBlock Origin

The [official repository](https://github.com/gorhill/uBlock) and
[@gorhill/ubo-core](https://www.npmjs.com/package/@gorhill/ubo-core) provide the
actual static network filtering engine. The installed package is 0.1.30,
GPL-3.0-or-later, requiring Node >=18. Its README warns that the API is early and
may change. Nothing in Zowy's Dart domain matcher is represented as that engine.

`tools/ubo-poc/proof.mjs` runs the unmodified package. It compiles controlled lists,
checks block, exception, first/third-party script conditions, important precedence,
and serialize/deserialize. `docs/ubo-proof-results.json` contains actual assertions,
rule explanations, desktop timing and process memory measurements. Reproduce:

```sh
cd tools/ubo-poc
npm ci --ignore-scripts
npm test
```

The package entrypoint imports `fs`, `path`, `url`, `module` and `util`, loads PSL
data synchronously and uses `createRequire` for optional WASM resources. A bare
embedded JS runtime cannot run this Node entrypoint unchanged. Its underlying JS
engine can fall back without WASM; missing WASM alone is **not** proof embedding
is impossible. A maintained platform adapter, PSL data, encoders/IDNA and module
loader are needed. That Android adapter has not been implemented or benchmarked.

[QuickJS](https://bellard.org/quickjs/) is MIT licensed and supports modern ES
modules. It is a credible lightweight candidate, but does not supply Node's
filesystem/module environment. Another option is Android WebView's JavaScript
runtime with a browser-specific adapter. A persistent hidden WebView adds Android
lifecycle and memory concerns; accepting browser-shaped fake request context for
DNS would still be misleading. Neither runtime has passed an Android uBO proof
in this project. No engine performance/memory numbers here apply to QuickJS.

[Brave adblock-rust](https://github.com/brave/adblock-rust), MPL-2.0, is a distinct
engine with ABP/uBO-inspired support. It could run through Dart FFI/JNI with native
builds, but would still require conservative extraction of DNS-enforceable rules.
It has been researched, not embedded. It is not labeled uBlock Origin.

## Active engine

Zowy currently uses an independently implemented Dart DNS subset: hosts entries,
plain ASCII domains, `||domain^`, `@@||domain^` and blocking `$important`. Plain
domains and hosts domains apply to subdomains in this DNS backend. IDNs must be
supplied as ASCII/punycode. Modifiers requiring URL, initiator, application or
resource context are unsupported. Unsupported and invalid counts are separate.
Regex is not evaluated, so downloaded regex cannot cause catastrophic backtracking.

Before official-core Android activation: implement the adapter, test serialized
cache corruption/versioning, bound evaluation, compare the rule corpus with the
desktop proof, measure 100k/500k/1m on Android, retain GPL notices/source, and only
pass network context genuinely available. A future owned-browser integration can
provide URL/initiator/type and DOM context; no browser module exists yet.
