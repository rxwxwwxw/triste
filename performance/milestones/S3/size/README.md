# S3 generation and build accounting

Run `python3 performance/milestones/S3/size/account.py` for the existing A5
four-grammar suite with default and lean-entry configurations. Input ownership
uses repository File/Buffer RAII. Commands have execution and memory bounds;
per-child POSIX wait4 measures native compiler peak RSS without GNU time.

Tiny/arithmetic/JSON compile successfully in both configurations. Their generated
source grows by 475/1596/2028 bytes; source generation is deterministic. Native
object sizes, generation times and compile times are in default.csv and lean.csv.
There are two generation samples and one compilation per case; do not infer a
reproducible timing gain from these single compilation measurements.

The 200-rule synthetic stress grammar generates deterministic source, growing
by 629 bytes. BOTH native configurations exceed the 4, 8 and final 16 GiB
compiler address-space budgets on this LLVM host. Their native success costs
are unavailable, with FAILED/N/A retained explicitly. All attempts are preserved
in metadata.json and failed-* directories. No further memory increase is made.
Runtime/test budgets remain 4 GiB; only the isolated stress compiler was allowed
16 GiB on this 61 GiB host. Native commands have a 300-second deadline and core
dumps disabled for the increased-budget attempts.

retry_large.py records the last bounded stress retry while retaining earlier
attempts; its /tmp inputs come from account.py. The missing-GNU-time attempt is
separately retained as native compilation NOT RUN, rather than a compiler failure.
