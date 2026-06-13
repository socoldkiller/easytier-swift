#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EASYTIER_DIR="$ROOT_DIR/Vendor/EasyTier"
OUT_DIR="$ROOT_DIR/Vendor/Frameworks"
HEADER_DIR="$OUT_DIR/include"
STATIC_DIR="$OUT_DIR/static"

cd "$ROOT_DIR"
export MACOSX_DEPLOYMENT_TARGET=14.0
if [[ -f Vendor/EasyTier/Cargo.toml ]]; then
  echo "Vendor/EasyTier already present."
else
  git submodule update --init --depth 1 Vendor/EasyTier
fi

mkdir -p "$OUT_DIR" "$HEADER_DIR" "$STATIC_DIR"

cat > "$HEADER_DIR/EasyTierFFI.h" <<'HEADER'
#pragma once
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

typedef struct KeyValuePair {
  const char *key;
  const char *value;
} KeyValuePair;

typedef void (*ConfigServerEventCallback)(const char *event_json, void *user_data);

int32_t parse_config(const char *cfg_str);
int32_t run_network_instance(const char *cfg_str);
int32_t retain_network_instance(const char **inst_names, uintptr_t length);
int32_t delete_network_instance(const char **inst_names, uintptr_t length);
int32_t list_instance(KeyValuePair *infos, uintptr_t max_length);
int32_t collect_network_infos(KeyValuePair *infos, uintptr_t max_length);
int32_t call_json_rpc(const char *service_name, const char *method_name, const char *domain_name, const char *payload_json, const char **out_response_json);
int32_t start_config_server_client(const char *config_server_url, const char *hostname, const char *machine_id, bool secure_mode, ConfigServerEventCallback callback, void *user_data);
int32_t stop_config_server_client(void);
int32_t is_config_server_client_connected(void);
void get_error_msg(const char **out);
void free_string(const char *s);
HEADER

build_target() {
  local target="$1"
  rustup target add "$target" >/dev/null
  cargo rustc --manifest-path "$EASYTIER_DIR/Cargo.toml" \
    -p easytier-ffi \
    --release \
    --target "$target" \
    --lib \
    --crate-type staticlib
}

build_target aarch64-apple-darwin
build_target x86_64-apple-darwin

ARM_STATIC="$EASYTIER_DIR/target/aarch64-apple-darwin/release/libeasytier_ffi.a"
X64_STATIC="$EASYTIER_DIR/target/x86_64-apple-darwin/release/libeasytier_ffi.a"
UNIVERSAL_STATIC="$STATIC_DIR/libeasytier_ffi.a"

lipo -create "$ARM_STATIC" "$X64_STATIC" -output "$UNIVERSAL_STATIC"

rm -rf "$OUT_DIR/EasyTierFFI.xcframework"
xcodebuild -create-xcframework \
  -library "$UNIVERSAL_STATIC" \
  -headers "$HEADER_DIR" \
  -output "$OUT_DIR/EasyTierFFI.xcframework"

cp "$HEADER_DIR/EasyTierFFI.h" "$ROOT_DIR/Sources/CEasyTierFFI/include/EasyTierFFI.h"

echo "Created static $OUT_DIR/EasyTierFFI.xcframework"
