#!/usr/bin/env bash
# Usage: run_velo.sh -v "<velo invocation>" -o <collection dir> [-f json|csv] -- Artifact[:--args K=V] ...
# Note: a <velo invocation> whose path contains spaces is not supported (it is word-split);
# move/symlink the binary to a space-free path instead.
set -u
VELO=""; OUT=""; FMT="jsonl"  # jsonl: one JSON object per line; --format json emits concatenated per-source arrays that do not parse as a single document
while [ $# -gt 0 ]; do
  case "$1" in
    -v) VELO="$2"; shift 2;;
    -o) OUT="$2"; shift 2;;
    -f) FMT="$2"; shift 2;;
    --) shift; break;;
    *) echo "unknown arg: $1" >&2; exit 2;;
  esac
done
if [ -z "$VELO" ] || [ -z "$OUT" ]; then echo "missing -v/-o" >&2; exit 2; fi
mkdir -p "$OUT"
LOG="$OUT/_collection_log.txt"
# Append (not truncate) so phase-by-phase runs into the same case folder accumulate one log.
echo "=== Collection started $(date -u +%FT%TZ) ===" >> "$LOG"
for item in "$@"; do
  name="${item%%:*}"; extra=""
  [ "$item" != "$name" ] && extra="${item#*:}"
  target="$OUT/$name.$FMT"
  start=$(date +%s)
  # shellcheck disable=SC2086
  $VELO --nobanner artifacts collect "$name" $extra --format "$FMT" > "$target" 2>>"$OUT/_errors.txt"
  ret=$?
  end=$(date +%s)
  rows=$(grep -c '"_Source"' "$target" 2>/dev/null || true)
  [ -z "$rows" ] && rows=0
  if [ "$ret" -eq 0 ]; then status="[DONE]"; else status="[FAIL exit=$ret]"; fi
  printf '%-14s %-40s %4ss  %s rows\n' "$status" "$name" "$((end-start))" "$rows" >> "$LOG"
done
echo "=== Collection finished $(date -u +%FT%TZ) ===" >> "$LOG"
cat "$LOG"
