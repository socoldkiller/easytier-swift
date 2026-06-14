#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

swift test
swift build --product EasyTierPrivilegedHelper

if [[ -f Vendor/Frameworks/static/libeasytier_ffi.a ]]; then
  for symbol in parse_config run_network_instance retain_network_instance collect_network_infos get_error_msg free_string; do
    if ! (nm -arch arm64 Vendor/Frameworks/static/libeasytier_ffi.a 2>/dev/null || true) | grep -q "_$symbol"; then
      echo "Missing FFI symbol: $symbol" >&2
      exit 1
    fi
  done
  echo "Static FFI library found and required symbols are exported."
else
  echo "Static FFI library not found; run ./scripts/build-ffi.sh before building the app."
  exit 1
fi

APP_PATH="$(./scripts/package-app.sh | tail -n 1)"
for file in \
  "$APP_PATH/Contents/MacOS/EasyTierMac" \
  "$APP_PATH/Contents/MacOS/EasyTierPrivilegedHelper" \
  "$APP_PATH/Contents/Library/LaunchDaemons/com.kkrainbow.easytier.mac.helper.plist"; do
  if [[ ! -e "$file" ]]; then
    echo "Missing packaged app component: $file" >&2
    exit 1
  fi
done

bundle_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP_PATH/Contents/Info.plist")"
if [[ "$bundle_version" == "1" ]]; then
  echo "Packaged app must use a fresh CFBundleVersion, not the static value 1." >&2
  exit 1
fi

helper_identifier="$(codesign -dv --verbose=4 "$APP_PATH/Contents/MacOS/EasyTierPrivilegedHelper" 2>&1 | sed -n 's/^Identifier=//p')"
if [[ "$helper_identifier" != "com.kkrainbow.easytier.mac.helper" ]]; then
  echo "Unexpected helper code signature identifier: $helper_identifier" >&2
  exit 1
fi

helper_info_plist="$(codesign -dv --verbose=4 "$APP_PATH/Contents/MacOS/EasyTierPrivilegedHelper" 2>&1 | sed -n '/^Info.plist/p')"
if [[ -z "$helper_info_plist" || "$helper_info_plist" == *"not bound"* ]]; then
  echo "Privileged helper must embed an Info.plist so SMAppService can identify its bundle." >&2
  exit 1
fi

helper_bundle_identifier="$(sfltool csinfo "$APP_PATH/Contents/MacOS/EasyTierPrivilegedHelper" 2>/dev/null | sed -n 's/^Bundle Identifier: //p')"
if [[ "$helper_bundle_identifier" != "com.kkrainbow.easytier.mac.helper" ]]; then
  echo "Unexpected helper bundle identifier: $helper_bundle_identifier" >&2
  exit 1
fi

if [[ -e "$APP_PATH/Contents/MacOS/EasyTierValidator" ]]; then
  echo "Packaged app must not include the removed EasyTierValidator binary." >&2
  exit 1
fi

echo "Packaged app contains GUI, privileged helper, and LaunchDaemon plist."
