#!/usr/bin/env bash
set -euo pipefail

fail() {
  printf 'validation error: %s\n' "$*" >&2
  exit 1
}

if [ "$#" -ne 1 ]; then
  printf 'Usage: %s path/to/RetroArchTV.ipa\n' "$0" >&2
  exit 2
fi

ipa_path="$1"
[ -f "$ipa_path" ] || fail "IPA does not exist: $ipa_path"

for command_name in unzip; do
  command -v "$command_name" >/dev/null 2>&1 ||
    fail "required command not found: $command_name"
done

unzip -tq "$ipa_path" >/dev/null || fail "ZIP integrity check failed"

validation_tmp_base="${TMPDIR:-$(dirname "$ipa_path")/.validation-tmp}"
mkdir -p "$validation_tmp_base"
validation_tmp="$(mktemp -d "$validation_tmp_base/mgba-multi-ipa.XXXXXX")"
cleanup() {
  if [ -d "$validation_tmp" ]; then
    rm -rf -- "$validation_tmp"
  fi
  rmdir "$validation_tmp_base" 2>/dev/null || true
}
trap cleanup EXIT

unzip -q "$ipa_path" -d "$validation_tmp"

shopt -s nullglob
apps=("$validation_tmp"/Payload/*.app)
shopt -u nullglob
[ "${#apps[@]}" -eq 1 ] || fail "IPA must contain exactly one app"
app_path="${apps[0]}"

[ -f "$app_path/Info.plist" ] || fail "app Info.plist is missing"
[ -f "$app_path/assets.zip" ] || fail "app assets.zip is missing"

core_framework="$app_path/Frameworks/mgba.multi.libretro.framework"
core_binary="$core_framework/mgba.multi.libretro"
[ -d "$core_framework" ] || fail "mGBA Multi framework is missing"
[ -f "$core_binary" ] || fail "mGBA Multi framework binary is missing"

unzip -tq "$app_path/assets.zip" >/dev/null ||
  fail "embedded assets.zip failed its integrity check"
unzip -l "$app_path/assets.zip" | grep -q 'info/mgba_multi_libretro.info' ||
  fail "mGBA Multi core metadata is missing"

if find "$validation_tmp" -type f \
  \( -iname '*.gba' -o -iname '*.gb' -o -iname '*.gbc' -o -iname '*.sgb' \) |
  grep -q .; then
  fail "the package unexpectedly contains a game ROM"
fi

if [ "$(uname -s)" = "Darwin" ]; then
  command -v xcrun >/dev/null 2>&1 || fail "xcrun is unavailable"

  xcrun lipo "$core_binary" -verify_arch arm64 >/dev/null 2>&1 ||
    fail "mGBA Multi framework is not arm64"
  core_build_info="$(xcrun vtool -show-build "$core_binary")" ||
    fail "could not inspect the mGBA Multi framework platform metadata"
  grep -qi 'platform.*TVOS' <<<"$core_build_info" ||
    fail "mGBA Multi framework is not a tvOS device binary"

  executable_name="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' \
    "$app_path/Info.plist")"
  app_binary="$app_path/$executable_name"
  [ -f "$app_binary" ] || fail "app executable is missing"
  xcrun lipo "$app_binary" -verify_arch arm64 >/dev/null 2>&1 ||
    fail "RetroArchTV executable is not arm64"
  app_build_info="$(xcrun vtool -show-build "$app_binary")" ||
    fail "could not inspect the RetroArchTV platform metadata"
  grep -qi 'platform.*TVOS' <<<"$app_build_info" ||
    fail "RetroArchTV executable is not a tvOS device binary"
fi

printf 'IPA validation passed: %s\n' "$ipa_path"
