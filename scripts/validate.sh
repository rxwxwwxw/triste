#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
for tool in dmd ldc2 gdc dfmt valgrind timeout python3 gcov rg; do
 command -v "$tool" >/dev/null || { echo "Required validation tool missing: $tool" >&2; exit 2; }
done
if rg -n --glob '*.d' 'import[[:space:]]+(std\.|[^;]*,[[:space:]]*std\.)' src tests examples scripts benchmark; then
 echo 'Phobos imports are forbidden in maintained D code' >&2; exit 1
fi
while IFS= read -r -d '' file; do
 dfmt "$file" | cmp -s "$file" - || { echo "Run dfmt -i on $file" >&2; exit 1; }
done < <(find src tests examples scripts benchmark -name '*.d' -print0)
for compiler in dmd ldc2 gdc; do
 DC=$compiler scripts/build.sh
 DC=$compiler scripts/examples.sh
done
timeout 10s python3 scripts/test_hooks.py
scripts/hotpaths.sh
scripts/coverage.sh
DC=ldc2 ASAN_OPTIONS=detect_leaks=1 scripts/build.sh -fsanitize=address -g
DC=gdc ASAN_OPTIONS=detect_leaks=1 scripts/build.sh -fsanitize=address,leak -g
DC=ldc2 scripts/build.sh -g -O0
timeout --preserve-status --kill-after=2s 120s valgrind --tool=memcheck --leak-check=full --show-leak-kinds=all --track-origins=yes --errors-for-leak-kinds=definite,indirect --error-exitcode=1 build/ldc2/tests --DRT-testmode=run-main

python3 scripts/benchmark_checks.py
