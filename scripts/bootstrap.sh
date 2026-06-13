#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

if ! command -v swift >/dev/null 2>&1; then
  echo "swift is required" >&2
  exit 1
fi

if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "xcodebuild is required" >&2
  exit 1
fi

if ! command -v cargo >/dev/null 2>&1; then
  echo "cargo is required for EasyTier FFI builds" >&2
  exit 1
fi

if [[ -f Vendor/EasyTier/Cargo.toml ]]; then
  echo "Vendor/EasyTier already present."
else
  git submodule update --init --depth 1 Vendor/EasyTier
fi

mkdir -p Vendor/Frameworks

echo "Swift: $(swift --version | head -n 1)"
echo "Xcode: $(xcodebuild -version | tr '\n' ' ')"
echo "Rust: $(cargo --version)"
echo "Bootstrap complete."
