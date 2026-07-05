#!/bin/bash
# Collect newsfragments/*.<type>.md into a dated CHANGELOG.md section, then
# delete the fragments that were consumed. See newsfragments/README.md.
#
# Usage:
#   ./build-changelog.sh <version>   # e.g. ./build-changelog.sh 1.1.0

set -e

VERSION="$1"
if [ -z "$VERSION" ]; then
  echo "Usage: $0 <version>" >&2
  exit 1
fi

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FRAGMENTS_DIR="$DIR/newsfragments"
CHANGELOG="$DIR/CHANGELOG.md"

# type -> section heading, in the order they should appear in the changelog.
# (parallel arrays, not an associative array, for /bin/bash 3.2 compatibility)
TYPES=(added changed fixed removed security doc misc)
HEADINGS=("Added" "Changed" "Fixed" "Removed" "Security" "Documentation" "Misc")

shopt -s nullglob
FRAGMENTS=("$FRAGMENTS_DIR"/*.*.md)
shopt -u nullglob
FRAGMENTS=("${FRAGMENTS[@]/$FRAGMENTS_DIR\/README.md/}")
# Drop the empty slot left by removing README.md, if it was present.
TMP=()
for f in "${FRAGMENTS[@]}"; do
  [ -n "$f" ] && TMP+=("$f")
done
FRAGMENTS=("${TMP[@]}")

if [ "${#FRAGMENTS[@]}" -eq 0 ]; then
  echo "No newsfragments to collect in $FRAGMENTS_DIR" >&2
  exit 1
fi

SECTION_FILE="$(mktemp)"
trap 'rm -f "$SECTION_FILE"' EXIT

echo "## $VERSION - $(date +%Y-%m-%d)" >> "$SECTION_FILE"

CONSUMED=()
for i in "${!TYPES[@]}"; do
  TYPE="${TYPES[$i]}"
  MATCHES=()
  for f in "${FRAGMENTS[@]}"; do
    base="$(basename "$f")"
    if [[ "$base" == *".$TYPE.md" ]]; then
      MATCHES+=("$f")
    fi
  done
  [ "${#MATCHES[@]}" -eq 0 ] && continue

  echo "" >> "$SECTION_FILE"
  echo "### ${HEADINGS[$i]}" >> "$SECTION_FILE"
  echo "" >> "$SECTION_FILE"
  for f in "${MATCHES[@]}"; do
    sed 's/^/- /' "$f" >> "$SECTION_FILE"
    CONSUMED+=("$f")
  done
done

if [ "${#CONSUMED[@]}" -eq 0 ]; then
  echo "No fragments with a recognized type found in $FRAGMENTS_DIR" >&2
  exit 1
fi

echo "" >> "$SECTION_FILE"
if [ -f "$CHANGELOG" ]; then
  cat "$CHANGELOG" >> "$SECTION_FILE"
fi
mv "$SECTION_FILE" "$CHANGELOG"
trap - EXIT

rm -f "${CONSUMED[@]}"

echo "Wrote $VERSION section to $CHANGELOG from ${#CONSUMED[@]} fragment(s)."

for f in "${FRAGMENTS[@]}"; do
  case " ${CONSUMED[*]} " in
    *" $f "*) ;;
    *) echo "Warning: $(basename "$f") has an unrecognized type, left in place." >&2 ;;
  esac
done
