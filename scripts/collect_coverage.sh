#!/usr/bin/env bash
# Called immediately after each executable, before another program can overwrite reports.
set -euo pipefail
root=$1
binary=$2
counter=${3:-unit}
mkdir -p "$root/lines/$counter" "$root/branches/$counter"
find . -maxdepth 1 -name '*.lst' -exec mv -t "$root/lines/$counter" {} +
base=$(basename "$binary")
directory=$(dirname "$binary")
find "$directory" -maxdepth 1 -name "$base-*.gcda" -exec mv -t "$root/branches/$counter" {} +
find "$directory" -maxdepth 1 \( -name "$base-*.gcno" -o -name "$base-*.profile" \) -exec cp -t "$root/branches/$counter" {} +
