#!/usr/bin/env bash
# Usage: run_velo.sh -v "<velo invocation>" -o <collection dir> [-f json|csv] -- Artifact[:--args K=V] ...
set -u
VELO=""; OUT=""; FMT="json"
while [ $# -gt 0 ]; do
  case "$1" in
    -v) VELO="$2"; shift 2;;
    -o) OUT="$2"; shift 2;;
    -f) FMT="$2"; shift 2;;
    --) shift; break;;
    *) echo "unknown arg: $1" >&2; exit 2;;
  esac
done
[ -z "$VELO" ] || [ -z "$OUT" ] && { echo "missing -v/-o" >&2; exit 2; }
mkdir -p "$OUT"
LOG="$OUT/_collection_log.txt"
echo "=== Collection started $(date -u +%FT%TZ) ===" > "$LOG"
for item in "$@"; do
  name="${item%%:*}"; extra=""
  [ "$item" != "$name" ] && extra="${item#*:}"
  target="$OUT/$name.$FMT"
  start=$(date +%s)
  # shellcheck disable=SC2086
  $VELO --nobanner artifacts collect "$name" $extra --format "$FMT" > "$target" 2>>"$OUT/_errors.txt" || true
  end=$(date +%s)
  rows=$(grep -c '"_Source"' "$target" 2>/dev/null || echo 0)
  printf '[DONE] %-40s %4ss  %s rows\n' "$name" "$((end-start))" "$rows" >> "$LOG"
done
echo "=== Collection finished $(date -u +%FT%TZ) ===" >> "$LOG"
cat "$LOG"
