# Changelog

All notable changes to the NPegged parser project are documented in this file.

## [Phase 2 Closeout] - 2026-10-18

### Added
- **User-Facing Parser Modes Guide:** Published comprehensive documentation in [`docs/PARSER_MODES.md`](docs/PARSER_MODES.md) detailing decision tables, API invocations, and performance trade-offs across all 5 parser modes.
- **Shared Output for Left Recursion (`version (NPeggedSharedOutput)`):** Persistent DAG fragment snapshots (`RecordFragment`) eliminating quadratic snapshot copying during left-recursive seed growth, achieving up to 2.16× speedups on deep recursion ($\ge 64$ terms).
- **Zero-Overhead Flat Specialization (`version (NPeggedFlatSpecialization)`):** Compile-time specialization of `RecordBuffer` ensuring non-recursive grammars (JSON, CSV) pay zero runtime penalty when shared output is enabled.
- **Pure-Island Scalar Execution (`version (NPeggedPureIslands)`):** Selective scalar lowering of proven pure sub-rules within action-bearing grammars.
- **Comprehensive Fragment Audit Suite:** Added [`tests/fragment_audit.d`](tests/fragment_audit.d) validating 10 memory safety and parent rebasing invariants under ASan and Valgrind Memcheck.
- **Crossover & Density Benchmarks:** Added [`benchmark/p09_crossover.d`](benchmark/p09_crossover.d) and [`benchmark/p13_tuning.d`](benchmark/p13_tuning.d).

### Changed
- **Performance Gate Baseline:** Tightened active performance targets toward $\le 1.5\times$ of handwritten D baselines now that the 5.0x milestone is achieved across all 513 gates (current median ratio: 2.132×).
- **Scanner Replay Optimization (H07):** Promoted failed-token fast-exit eliminating 99.8% of diagnostic scanner replays.
