#!/usr/bin/env bash
set -euo pipefail

target="${1:-${TMPDIR:-/tmp}/mymacfinder-large-fixture}"
file_count="${2:-5000}"
folder_count="${3:-250}"

if ! [[ "$file_count" =~ ^[0-9]+$ && "$folder_count" =~ ^[0-9]+$ ]]; then
  echo "Usage: $0 [target] [file_count] [folder_count]" >&2
  exit 2
fi

mkdir -p "$target"

i=1
while (( i <= file_count )); do
  printf -v number "%05d" "$i"
  printf "fixture file %s\n" "$number" > "$target/file-$number.txt"
  ((i += 1))
done

i=1
while (( i <= folder_count )); do
  printf -v number "%05d" "$i"
  mkdir -p "$target/folder-$number"
  ((i += 1))
done

echo "$target"
