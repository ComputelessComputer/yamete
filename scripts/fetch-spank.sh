#!/usr/bin/env bash

set -euo pipefail

REPO="taigrr/spank"
OUTPUT_DIR="${1:-.build/spank}"

mkdir -p "$OUTPUT_DIR"

if [[ -x "$OUTPUT_DIR/spank" ]]; then
  echo "$OUTPUT_DIR/spank"
  exit 0
fi

if command -v gh >/dev/null 2>&1; then
  echo "Fetching spank via gh CLI..." >&2
  gh release download --repo "$REPO" --pattern "*darwin_arm64.tar.gz" --dir "$OUTPUT_DIR"
  TARBALL=$(ls "$OUTPUT_DIR"/*darwin_arm64.tar.gz 2>/dev/null | head -1)
  if [[ -z "$TARBALL" ]]; then
    echo "Error: gh release download did not produce a darwin_arm64 tarball" >&2
    exit 1
  fi
else
  TAG=$(curl -sfL "https://api.github.com/repos/$REPO/releases/latest" \
    | grep '"tag_name"' | head -1 | sed 's/.*: *"//;s/".*//')

  if [[ -z "${TAG:-}" ]]; then
    echo "Error: could not resolve latest spank release tag" >&2
    exit 1
  fi

  VERSION="${TAG#v}"
  TARBALL_NAME="spank_${VERSION}_darwin_arm64.tar.gz"
  URL="https://github.com/$REPO/releases/download/$TAG/$TARBALL_NAME"
  TARBALL="$OUTPUT_DIR/$TARBALL_NAME"

  echo "Fetching spank $TAG from $URL..." >&2
  curl -sfL "$URL" -o "$TARBALL"
fi

tar -xzf "$TARBALL" -C "$OUTPUT_DIR"
rm -f "$TARBALL"

if [[ ! -x "$OUTPUT_DIR/spank" ]]; then
  echo "Error: spank binary not found after extraction" >&2
  exit 1
fi

echo "$OUTPUT_DIR/spank"
