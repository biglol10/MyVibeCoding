#!/usr/bin/env bash
set -euo pipefail

target="${1:-${TMPDIR:-/tmp}/mymacfinder-file-ops-qa}"
rm -rf "$target"
mkdir -p "$target/source" "$target/dest" "$target/drag-target" "$target/zips/nested"

printf "source alpha\n" > "$target/source/alpha.txt"
printf "source collide\n" > "$target/source/collide.txt"
printf "destination collide\n" > "$target/dest/collide.txt"
printf "rename original\n" > "$target/source/rename-me.txt"
printf "duplicate original\n" > "$target/source/duplicate-me.txt"
mkdir -p "$target/source/folder-a/child"
printf "folder child\n" > "$target/source/folder-a/child/file.txt"

printf "zip readme\n" > "$target/zips/nested/readme.txt"
printf "zip collide\n" > "$target/zips/collide.txt"
(
  cd "$target/zips"
  /usr/bin/zip -qr "$target/source/archive.zip" nested collide.txt
)
mkdir -p "$target/source/archive"
printf "existing archive folder\n" > "$target/source/archive/existing.txt"

"$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/create-large-folder-fixture.sh" "$target/large" 1500 100 >/dev/null

echo "$target"
