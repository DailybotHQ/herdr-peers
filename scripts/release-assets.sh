#!/usr/bin/env bash
# Build the assets of a GitHub release from a checkout of its tag.
#
#   bash scripts/release-assets.sh [--root DIR] vX.Y.Z OUTDIR
#
# Writes into OUTDIR:
#   RELEASE_NOTES.md  the `## [X.Y.Z]` section of CHANGELOG.md
#   SHA256SUMS        sha256 of every shipped file (skills/, bin/, LICENSE),
#                     in the format `shasum -a 256 -c SHA256SUMS` verifies
#
# Used by .github/workflows/release.yml; runnable locally to reproduce a
# published release. Exit codes: 0 ok, 1 missing notes or files, 2 usage.
set -eu

ROOT=.
if [ "${1:-}" = --root ]; then
  [ $# -ge 2 ] || { echo "usage: $0 [--root DIR] vX.Y.Z OUTDIR" >&2; exit 2; }
  ROOT=$2
  shift 2
fi
if [ $# -ne 2 ]; then
  echo "usage: $0 [--root DIR] vX.Y.Z OUTDIR" >&2
  exit 2
fi
tag=$1
out=$2
if ! printf '%s\n' "$tag" | grep -qE '^v[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?$'; then
  echo "release-assets: '$tag' is not a vX.Y.Z tag" >&2
  exit 2
fi
version=${tag#v}

mkdir -p "$out"
out=$(cd "$out" && pwd)
cd "$ROOT"

# Notes: from the version heading to the next `## [` heading, without the
# heading itself and without surrounding blank lines.
awk -v v="$version" '
  index($0, "## [" v "]") == 1 { on = 1; next }
  on && /^## \[/ { exit }
  on && /^\[[^]]+\]: / { next }
  on { print }
' CHANGELOG.md | sed -e '/./,$!d' >"$out/RELEASE_NOTES.md"
if ! grep -q . "$out/RELEASE_NOTES.md"; then
  echo "release-assets: CHANGELOG.md has no '## [$version]' section" >&2
  exit 1
fi

files=$(git ls-files skills bin LICENSE | LC_ALL=C sort)
if [ -z "$files" ]; then
  echo "release-assets: no shipped files tracked under skills/, bin/, LICENSE" >&2
  exit 1
fi
printf '%s\n' "$files" | tr '\n' '\0' | xargs -0 shasum -a 256 >"$out/SHA256SUMS"
echo "release-assets: $tag -> $out (RELEASE_NOTES.md, SHA256SUMS: $(grep -c . "$out/SHA256SUMS") files)"
