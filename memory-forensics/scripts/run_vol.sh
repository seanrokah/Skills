#!/usr/bin/env bash
# Usage: run_vol.sh -v "<vol invocation>" -f <image> -o <artifacts dir> [-s <symbols>] -- plugin[:extra] ...
set -u
VOL=""; IMG=""; OUT=""; SYM=""
while [ $# -gt 0 ]; do
  case "$1" in
    -v) VOL="$2"; shift 2;;
    -f) IMG="$2"; shift 2;;
    -o) OUT="$2"; shift 2;;
    -s) SYM="$2"; shift 2;;
    --) shift; break;;
    *) echo "unknown arg: $1" >&2; exit 2;;
  esac
done
[ -z "$VOL" ] || [ -z "$IMG" ] || [ -z "$OUT" ] && { echo "missing -v/-f/-o" >&2; exit 2; }
mkdir -p "$OUT"
LOG="$OUT/_collection_log.txt"
echo "=== Collection started $(date -u +%FT%TZ) ===" > "$LOG"
SYMARGS=""; [ -n "$SYM" ] && SYMARGS="-s $SYM"
for item in "$@"; do
  name="${item%%:*}"; extra=""
  [ "$item" != "$name" ] && extra="${item#*:}"
  target="$OUT/$name.txt"
  start=$(date +%s)
  # shellcheck disable=SC2086
  $VOL -f "$IMG" $SYMARGS "$name" $extra > "$target" 2>/dev/null || true
  end=$(date +%s)
  lines=$(wc -l < "$target" 2>/dev/null | tr -d ' ')
  printf '[DONE] %-34s %4ss  %s lines\n' "$name" "$((end-start))" "$lines" >> "$LOG"
done
echo "=== Collection finished $(date -u +%FT%TZ) ===" >> "$LOG"
cat "$LOG"
