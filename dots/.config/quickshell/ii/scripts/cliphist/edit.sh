#!/usr/bin/env bash
# Usage: edit.sh <cliphist list line> <cliphist binary>
# Opens the full entry in nvim (kitty). If it changed, replaces the entry and
# prints the new top `cliphist list` line on stdout.
entry="$1"; bin="${2:-cliphist}"
dir=/tmp/quickshell/media/cliphist-edit
mkdir -p "$dir"
f=$(mktemp "$dir/clip-XXXXXX.txt")
trap 'rm -f "$f" "$f.orig"' EXIT

printf '%s\n' "$entry" | "$bin" decode > "$f" || exit 1
cp "$f" "$f.orig"
kitty --class clipboard-edit -e nvim "+set nofixeol" "$f"
cmp -s "$f" "$f.orig" && exit 0

printf '%s\n' "$entry" | "$bin" delete
before=$("$bin" list | head -1 | cut -f1)
wl-copy < "$f"
for _ in $(seq 30); do
    top=$("$bin" list | head -1)
    [[ -n "$top" && "${top%%$'\t'*}" != "$before" ]] && { printf '%s\n' "$top"; exit 0; }
    sleep 0.1
done
