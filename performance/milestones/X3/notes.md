# X3 — Offline autotuning (tool delivered; no profile adopted)

`performance/scripts/autotune.py NAME=RUN_DIR ...` reads recorded `summary.csv` files, compares npegged median times on the workloads the
candidates share, and freezes one choice per family. The first candidate is the default; another wins only with a >=3% geomean gain on
>=3 shared workloads and no workload worse than 1.25x. Nothing is measured at parse time and nothing is collected by the tool.
It has a built-in self-test (run on every invocation). `profile-example.json` is the output for two recorded baselines
(`20261020T151538Z` vs `20261020T162736Z`): both families keep the default, so no profile change is justified by that data.

Not done: a combinators-vs-direct run set (D1 stays "keep combinators"), a backend-aware consumer in the generator, and architecture
keyed profiles. The tool is ready for those inputs; no gain is claimed.
