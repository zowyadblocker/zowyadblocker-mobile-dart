# Desktop benchmarks

Measured 2026-11-20 using Dart 3.14.0 JIT, Windows x64. These are synthetic domain
fixtures, not Android, cold-start, battery or real-list results. Reproduce with
`dart run tool/benchmark.dart`. Matching performs 100,000 positive lookups.

| Rules | Compile ms | 100k matches ms | Process RSS after (bytes) | Process peak RSS (bytes) |
|---:|---:|---:|---:|---:|
| 100,000 | 238 | 144 | 260,063,232 | 273,965,056 |
| 500,000 | 1,347 | 98 | 324,403,200 | 343,556,096 |
| 1,000,000 | 2,318 | 91 | 439,484,416 | 488,554,496 |

RSS includes the Dart VM, generated list text and potentially earlier iterations;
the raw measurements are in `dart-benchmark-results.jsonl`.
it is not isolated engine allocation. JIT/GC effects explain non-monotonic values.
These numbers expose meaningful memory cost at large list sizes; no “lightweight
at one million rules” claim is made. Profile Android ARM64 before raising limits.

The independent official-uBO proof results are in `ubo-proof-results.json` and
use a small controlled fixture. They are not comparable to the Dart million-rule
benchmark, nor evidence of an embedded Android uBO engine.
