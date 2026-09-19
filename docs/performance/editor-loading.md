# Editor load baseline — 2026-09-19

Measurements use the release build on the development Mac (Apple silicon),
TextBuffer revision 3dfbfc13fe4e7f898a3b7c3d13d3eb1451eb8386.

Fixture: random-text-100MiB.txt, 104,857,600 bytes, ASCII/UTF-8, LF endings,
809,757 logical lines including the empty final line. Previously accessed local
file; filesystem caches were not cleared. Three separate process launches.

## Reproduce

Build once (compilation is excluded from the measurements):

    swift build -c release --product EditorBenchmark
    COMMANDER_PROFILE_EDITOR=1 /usr/bin/time -l .build/release/EditorBenchmark /tmp/commander-editor-preview/random-text-100MiB.txt

The benchmark calls the same EditorFile.open and EditorDocuments.make entry
points used by the app. It then retrieves the first 40 lines through the document
API. It does not include AppKit layout, rendering, or event-loop latency.
The environment flag also enables stage logging in the app; logging is disabled
by default. No document contents are logged.

## Results

| Stage | Run 1 (seconds) | Run 2 | Run 3 |
| --- | ---: | ---: | ---: |
| Resolve path and open | 0.0020 | 0.0024 | 0.0019 |
| Read bytes | 0.0102 | 0.0100 | 0.0112 |
| Decode UTF-8 | 0.0099 | 0.0078 | 0.0099 |
| Check for NUL | 1.5940 | 1.6010 | 1.6306 |
| Detect line endings | 3.8963 | 3.9063 | 3.9567 |
| Normalize on open | 0.7681 | 0.7552 | 0.7615 |
| Normalize again on document creation | 0.7491 | 0.7515 | 0.7624 |
| Build TextBuffer rope | 0.0607 | 0.0532 | 0.0543 |
| Build line-start index | 0.2057 | 0.2055 | 0.2088 |
| **Document ready, total** | **7.2969** | **7.2940** | **7.3986** |
| Retrieve first 40 lines | 0.000297 | 0.000236 | 0.000270 |

Run 3 splits line-ending detection further:

- Make text without CRLF: 0.3884 s.
- Search original text for CRLF: 1.9463 s.
- Search remaining text for lone CR: 1.6220 s.
- Search remaining text for LF: 0.000007 s (present near the beginning).

Peak RSS reported by time -l: 494,157,824 bytes (run 1) and
494,747,648 bytes (run 3), approximately 471–472 MiB.
This is the standalone benchmark process, not the full app.

Vim baseline, three runs:

    /usr/bin/vi -u NONE -U NONE -i NONE -N -n -es /tmp/commander-editor-preview/random-text-100MiB.txt -c 'qa!'

Elapsed subprocess time: 0.1423, 0.1424, 0.1469 seconds. Exit status 0 in
all runs. System Vim 9.1, patches 1–1752. This is a minimal headless load
and exit with configuration, viminfo, and swap disabled; it is not an
interactive time-to-first-frame comparison.

## Interpretation

Approximately 96% of document preparation is our string checks and newline
processing. Disk reading and rope construction are not the principal bottlenecks
for this fixture. The generic String searches for absent NUL/CR/CRLF each scan
the full text. The second normalization is redundant.

Next optimization to evaluate: combine NUL and newline detection in a single
UTF-8 byte pass, skip normalization for LF-only text, and normalize only once.
No backend replacement or lazy loading is justified by this baseline alone.
These findings are specific to this ASCII, many-short-lines fixture; Unicode
content, extremely long lines, and uncached/network files need separate samples.

## After single-pass preparation — 2026-09-19

Same release benchmark and previously accessed 100 MiB fixture, three fresh
processes. The byte scan combines NUL detection, newline detection, and CR/CRLF
normalization. LF-only input does not allocate a rewritten byte buffer. UTF-8
decoding/validation still runs once. Document creation from EditorFile no longer
normalizes the already prepared text.

| Stage | Run 1 (seconds) | Run 2 | Run 3 |
| --- | ---: | ---: | ---: |
| Resolve path and open | 0.003264 | 0.001979 | 0.004223 |
| Read bytes | 0.015921 | 0.009991 | 0.010940 |
| Prepare text, including UTF-8 decoding | 0.074929 | 0.075056 | 0.070510 |
| Build rope | 0.054503 | 0.055382 | 0.058733 |
| Build line index | 0.201979 | 0.205030 | 0.203519 |
| **Document ready** | **0.351092** | **0.347899** | **0.348411** |

Median document preparation fell from 7.296881 s to 0.348411 s (20.9× faster).
The largest remaining stage is line-index construction. This comparison still
excludes GUI rendering and does not imply the same speedup for every file type.

## Combined line indexing and ASCII block scan — 2026-09-19

Line-start UTF-16 offsets are now collected during the preparation scan and
passed to the document, eliminating the separate ~203 ms UTF-16 traversal.
An eight-byte ASCII fast path skips chunks without NUL, CR, LF, or non-ASCII
bytes. It uses bounded unaligned loads and the standard zero-byte detection
identity. Other bytes follow the scalar path, counting UTF-16 units from UTF-8
leading bytes; the decoder still rejects invalid UTF-8 before the index is used.
Offsets account for CRLF contraction and supplementary Unicode scalars.

Five fresh release benchmark processes on the same warm-cache fixture:

| Run | Read bytes (ms) | Prepare text + index (ms) | Build rope (ms) | Document ready (ms) |
| --- | ---: | ---: | ---: | ---: |
| 1 | 9.888 | 37.629 | 61.858 | 111.929 |
| 2 | 10.737 | 37.978 | 55.342 | 106.931 |
| 3 | 10.552 | 37.203 | 55.138 | 105.577 |
| 4 | 10.177 | 40.532 | 59.914 | 113.015 |
| 5 | 10.188 | 43.414 | 55.048 | 111.190 |

Median: 111.190 ms, versus 348.411 ms after the first optimization and
7,296.881 ms originally. First-page retrieval adds 0.159–0.205 ms.
The 100–150 ms target is met for document preparation on this fixture.
These are not GUI first-frame timings or a guarantee for uncached, remote,
CRLF-heavy, or non-ASCII files.

Regression coverage checks line ranges, Unicode, edits/undo, all newline
styles, and NUL/invalid UTF-8 at offsets spanning both sides of eight-byte
block boundaries. Saved snapshots without a prepared index rebuild it when
used to create a new document; ordinary in-memory document creation retains
the existing normalization and index path.

## Stack sampling and flame graph — 2026-09-19

Profiled the unchanged optimized release load path using macOS sample at a 1 ms
interval for 10 seconds. The benchmark performed 150 load/read-page/release cycles
with an autorelease pool per iteration, without stage logging. The repeated-loop
profile intentionally includes document teardown; it must not be confused with
the document-ready latency measured before teardown.

7,587 samples contain benchmarkLoad. Startup/dyld samples outside that function
were excluded. Sampling is statistical, includes on-stack waits, and has overhead;
counts are not exact per-function elapsed times or allocation measurements.
Optimized/inlined symbols and source-line attribution can be approximate.

| Region | Inclusive samples | Share of load-cycle samples |
| --- | ---: | ---: |
| Document/rope construction | 3,963 | 52.23% |
| TextRope.Summary.of (inside construction) | 3,032 | 39.96% |
| File opening and preparation | 2,891 | 38.10% |
| EditorTextPreparation.scan (inside preparation) | 2,459 | 32.41% |
| Document destruction | 726 | 9.57% |

Nested rows overlap their parent rows and must not be added together.
Summary.of has 3,002 self samples. It calculates UTF-16 length and newline counts
for each rope chunk. Source attribution concentrates at the withUTF8 closure;
it does not by itself establish which instruction in that closure dominates.
This function is a stronger next profiling/optimization candidate than tree
balancing. Changing it would mean changing the dependency, not just our adapter.

Three additional fresh-process, unprofiled runs with stage logging gave document
ready times 131.786, 105.701, and 105.282 ms. The first had slower path resolution
and rope construction. This supports the prior ~110 ms result; repeated-loop
timings benefit further from warm allocator state and are not substituted for it.

Artifacts:

- [Interactive flame graph](profiles/editor-load-100MiB.html): click a frame to
  zoom, Back/Reset, function-name highlighting.
- [Static SVG](profiles/editor-load-100MiB.svg).
- [Original sample report](profiles/editor-load-100MiB.sample.txt).
- [Folded stacks](profiles/editor-load-100MiB.folded).
- [Inclusive/self counts](profiles/editor-load-100MiB.summary.txt).
- [Fresh-process timings](profiles/editor-load-100MiB.timings.txt).

Reproduce:

    swift build -c release --product EditorBenchmark
    .build/release/EditorBenchmark /tmp/commander-editor-preview/random-text-100MiB.txt 150 > /tmp/editor-loads.log &
    benchmark_pid=$!
    sample "$benchmark_pid" 10 1 -mayDie -file /tmp/editor-stacks.txt
    wait "$benchmark_pid"
    python3 scripts/editor-flamegraph.py /tmp/editor-stacks.txt /tmp/editor-flame

Flame widths represent inclusive stack sample counts, not chronology. The bottom
frame is the caller and frames above it are callees. The full graph includes
deep recursive cleanup stacks; zoom into make(file:) or open(_:) to inspect
opening alone. No editor implementation or TextBuffer dependency was changed
during this profiling pass.

## Control-character processing ablation — 2026-09-19

An isolated experiment copies the current scanner into a temporary standalone
release/WMO executable. It does not alter EditorCore or the app. It compares:

1. Full scanner: current NUL checks, newline detection/normalization, UTF-16
   offsets, and line-start array.
2. Checks only: retain the NUL/LF/CR tests in the eight-byte fast-path predicate
   and scalar fallback, but perform only UTF-16 counting in that fallback.
3. No controls: omit control-character tests from the block predicate and all
   control-character handling; retain ASCII detection and UTF-16 counting.

The last two modes deliberately do NOT implement correct editor preparation.
They demonstrate work-removal bounds, not a safe replacement.

Same local fixture path, now 104,857,612 bytes (100 MiB + 12 bytes, changed since
the earlier captures). All three variants in this comparison use the same Data
snapshot. The JSON records its SHA-256. Three warm-up rounds are discarded and
15 measured rounds rotate execution order. File I/O, UTF-8 decoding, result
consumption/destruction, and rope construction are outside timed sections.
The UTF-16 counts from both stripped variants are checked against Swift's
decoder, and outputs are consumed to prevent removal as dead code.

| Mode | Median scanner time |
| --- | ---: |
| Full | 24.546 ms |
| Checks only | 17.157 ms |
| No control handling | 8.507 ms |

Removing all control handling reduces this scan by ~16 ms (~65%). Retaining
only block checks costs ~8.65 ms over the stripped scan; full processing costs
~7.39 ms more than checks alone. These differences include extra instructions,
different fast-path hit rates, scalar fallback work, and array writes/allocations.
They do NOT isolate branch misprediction cost, and the stripped scanner cannot
be used to claim a corresponding correctness-preserving optimization.

Reproduce:

    python3 scripts/benchmark-scan-controls.py /tmp/commander-editor-preview/random-text-100MiB.txt --rounds 15 --output /tmp/scan-controls.json

[Raw timings](profiles/scan-controls-ablation.json).
