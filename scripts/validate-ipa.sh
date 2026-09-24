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

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
kit_root="$(cd "$script_dir/.." && pwd)"
# shellcheck source=../versions.env
source "$kit_root/versions.env"
expected_app_build_number="${APP_BUILD_NUMBER:-$APP_BUILD_NUMBER_DEFAULT}"
expected_app_display_name="${APP_DISPLAY_NAME:-$APP_DISPLAY_NAME_DEFAULT}"
expected_bundle_id="${BUNDLE_ID:-$BUNDLE_ID_DEFAULT}"
expected_tvos_target="${TVOS_DEPLOYMENT_TARGET:-$TVOS_DEPLOYMENT_TARGET_DEFAULT}"

command -v unzip >/dev/null 2>&1 || fail "required command not found: unzip"
unzip -tq "$ipa_path" >/dev/null || fail "ZIP integrity check failed"

archive_entries="$(unzip -Z1 "$ipa_path")" || fail "could not list IPA entries"
[ -n "$archive_entries" ] || fail "IPA is empty"
while IFS= read -r archive_entry; do
  [ -n "$archive_entry" ] || continue
  case "$archive_entry" in
    Payload|Payload/*) ;;
    *) fail "unexpected top-level IPA entry: $archive_entry" ;;
  esac
  case "/$archive_entry/" in
    *'/../'*|*'/./'*) fail "unsafe IPA entry: $archive_entry" ;;
  esac
  case "$archive_entry" in
    /*|*'\\'*) fail "unsafe IPA entry name: $archive_entry" ;;
  esac
done <<<"$archive_entries"
if grep -E '(^|/)(__MACOSX|\.DS_Store)(/|$)|(^|/)\._' \
  <<<"$archive_entries" >/dev/null; then
  fail "IPA contains Finder metadata or AppleDouble files"
fi

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
payload_items=("$validation_tmp"/Payload/*)
apps=("$validation_tmp"/Payload/*.app)
shopt -u nullglob
[ "${#payload_items[@]}" -eq 1 ] ||
  fail "Payload must contain exactly one item"
[ "${#apps[@]}" -eq 1 ] || fail "IPA must contain exactly one app"
app_path="${apps[0]}"

[ -f "$app_path/Info.plist" ] || fail "app Info.plist is missing"
[ -f "$app_path/assets.zip" ] || fail "app assets.zip is missing"
[ ! -e "$app_path/PlugIns" ] || fail "sideload IPA must not contain PlugIns"
[ ! -e "$app_path/_CodeSignature" ] ||
  fail "top-level app must not retain an Xcode signature"
if find "$app_path" -type d -name '*.appex' -print -quit | grep -q .; then
  fail "sideload IPA must not contain an app extension"
fi
if find "$app_path" -type f -name 'embedded.mobileprovision' -print -quit |
  grep -q .; then
  fail "unsigned IPA must not contain a provisioning profile"
fi
if find "$app_path" -type f -name '._*' -print -quit | grep -q .; then
  fail "app bundle contains AppleDouble files"
fi

core_framework="$app_path/Frameworks/mgba.multi.libretro.framework"
core_binary="$core_framework/mgba.multi.libretro"
stock_core_framework="$app_path/Frameworks/mgba.libretro.framework"
[ -d "$core_framework" ] || fail "mGBA Multi framework is missing"
[ -f "$core_binary" ] || fail "mGBA Multi framework binary is missing"
[ -x "$core_binary" ] || fail "mGBA Multi framework binary is not executable"
[ ! -e "$stock_core_framework" ] ||
  fail "stock mGBA framework must not be present"

unzip -tq "$app_path/assets.zip" >/dev/null ||
  fail "embedded assets.zip failed its integrity check"
asset_entries="$(unzip -Z1 "$app_path/assets.zip")" ||
  fail "could not list the embedded assets.zip"
grep -Fx 'info/mgba_multi_libretro.info' <<<"$asset_entries" >/dev/null ||
  fail "mGBA Multi core metadata is missing"
core_info="$(unzip -p "$app_path/assets.zip" info/mgba_multi_libretro.info)" ||
  fail "could not read mGBA Multi core metadata"
grep -F "display_version = \"0.11-dev-multi.$CUSTOM_CORE_VERSION\"" \
  <<<"$core_info" >/dev/null ||
  fail "mGBA Multi $CUSTOM_CORE_VERSION metadata is missing"
grep -F 'supported_extensions = "gba"' <<<"$core_info" >/dev/null ||
  fail "barebones core metadata must be GBA-only"

if find "$validation_tmp" -type f \
  \( -iname '*.gba' -o -iname '*.gb' -o -iname '*.gbc' -o -iname '*.sgb' \) \
  -print -quit |
  grep -q .; then
  fail "the package unexpectedly contains a game ROM"
fi

if [ "$(uname -s)" = "Darwin" ]; then
  for command_name in xcrun strings codesign; do
    command -v "$command_name" >/dev/null 2>&1 ||
      fail "required command not found: $command_name"
  done
  [ -x /usr/libexec/PlistBuddy ] || fail "PlistBuddy is unavailable"

  plist_value() {
    /usr/libexec/PlistBuddy -c "Print :$1" "$app_path/Info.plist" 2>/dev/null ||
      fail "app Info.plist is missing $1"
  }

  [ "$(plist_value CFBundleIdentifier)" = "$expected_bundle_id" ] ||
    fail "unexpected CFBundleIdentifier"
  [ "$(plist_value ALTBundleIdentifier)" = "$expected_bundle_id" ] ||
    fail "unexpected ALTBundleIdentifier"
  [ "$(plist_value CFBundleDisplayName)" = "$expected_app_display_name" ] ||
    fail "unexpected CFBundleDisplayName"
  [ "$(plist_value CFBundleVersion)" = "$expected_app_build_number" ] ||
    fail "unexpected CFBundleVersion"
  [ "$(plist_value CFBundleShortVersionString)" = "$RETROARCH_VERSION" ] ||
    fail "unexpected CFBundleShortVersionString"
  [ "$(plist_value CFBundlePackageType)" = "APPL" ] ||
    fail "app package type is not APPL"
  [ "$(plist_value CFBundleSupportedPlatforms:0)" = "AppleTVOS" ] ||
    fail "app does not declare AppleTVOS support"
  [ "$(plist_value DTPlatformName)" = "appletvos" ] ||
    fail "app was not built for the Apple TV device platform"
  [ "$(plist_value UIDeviceFamily:0)" = "3" ] ||
    fail "app UIDeviceFamily is not Apple TV"
  if /usr/libexec/PlistBuddy -c 'Print :UIDeviceFamily:1' \
    "$app_path/Info.plist" >/dev/null 2>&1; then
    fail "app declares a non-Apple-TV device family"
  fi
  [ "$(plist_value MinimumOSVersion)" = "$expected_tvos_target" ] ||
    fail "unexpected minimum tvOS version"

  executable_name="$(plist_value CFBundleExecutable)"
  app_binary="$app_path/$executable_name"
  [ -f "$app_binary" ] || fail "app executable is missing"
  [ -x "$app_binary" ] || fail "app executable bit is missing"

  app_archs="$(xcrun lipo "$app_binary" -archs)" ||
    fail "could not inspect the RetroArchTV architectures"
  case " $app_archs " in
    *" arm64 "*) ;;
    *) fail "RetroArchTV executable is not arm64 (architectures: ${app_archs:-none})" ;;
  esac
  app_build_info="$(xcrun vtool -show-build "$app_binary")" ||
    fail "could not inspect the RetroArchTV platform metadata"
  grep -qi 'platform.*TVOS' <<<"$app_build_info" ||
    fail "RetroArchTV executable is not a tvOS device binary"

  core_archs="$(xcrun lipo "$core_binary" -archs)" ||
    fail "could not inspect the mGBA Multi framework architectures"
  case " $core_archs " in
    *" arm64 "*) ;;
    *) fail "mGBA Multi framework is not arm64 (architectures: ${core_archs:-none})" ;;
  esac
  core_build_info="$(xcrun vtool -show-build "$core_binary")" ||
    fail "could not inspect the mGBA Multi framework platform metadata"
  grep -qi 'platform.*TVOS' <<<"$core_build_info" ||
    fail "mGBA Multi framework is not a tvOS device binary"

  expected_install_name='@rpath/mgba.multi.libretro.framework/mgba.multi.libretro'
  core_install_names="$(xcrun otool -D "$core_binary")" ||
    fail "could not inspect the mGBA Multi install name"
  grep -Fx "$expected_install_name" <<<"$core_install_names" >/dev/null ||
    fail "mGBA Multi framework has an unexpected install name"

  core_symbols="$(xcrun nm -g "$core_binary")" ||
    fail "could not inspect the mGBA Multi symbols"
  core_all_symbols="$(xcrun nm "$core_binary")" ||
    fail "could not inspect all mGBA Multi symbols"
  grep -q '_pthread_create' <<<"$core_symbols" ||
    fail "mGBA Multi is missing its persistent pthread workers"
  if grep -E '_mCoreThread|_GBASIOLockstep|_GBSIOLockstep' \
    <<<"$core_all_symbols" >/dev/null; then
    fail "mGBA Multi contains forbidden mCoreThread or link-cable symbols"
  fi
  for retro_symbol in \
    retro_init retro_deinit retro_get_system_info retro_set_environment \
    retro_load_game retro_unload_game retro_run; do
    grep -Eq "[[:space:]]_?${retro_symbol}$" <<<"$core_symbols" ||
      fail "mGBA Multi does not export ${retro_symbol}"
  done
  core_strings="$(strings "$core_binary")" ||
    fail "could not inspect the mGBA Multi strings"
  if grep -Ei \
    'mgba_multi_link|mgba_link_[23]|Local link cable|threaded link|mgba_multi_speed|speed target|Toggle individual speed|mgba_multi_audio|mgba_multi_[23]|Load Subsystem|mGBA Multi \(2 ROMs\)|mGBA Multi \(3 ROMs\)' \
    <<<"$core_strings" >/dev/null; then
    fail "mGBA Multi contains removed link, speed, or subsystem features"
  fi

  framework_count=0
  while IFS= read -r -d '' framework_path; do
    framework_count=$((framework_count + 1))
    framework_plist="$framework_path/Info.plist"
    [ -f "$framework_plist" ] ||
      fail "framework Info.plist is missing: $framework_path"
    framework_executable="$(/usr/libexec/PlistBuddy \
      -c 'Print :CFBundleExecutable' "$framework_plist")" ||
      fail "framework executable name is missing: $framework_path"
    [ -f "$framework_path/$framework_executable" ] ||
      fail "framework executable is missing: $framework_path/$framework_executable"
    [ -x "$framework_path/$framework_executable" ] ||
      fail "framework executable bit is missing: $framework_path/$framework_executable"
    codesign --verify --strict "$framework_path" ||
      fail "framework signature is invalid: $framework_path"
  done < <(find "$app_path/Frameworks" -type d -name '*.framework' -print0)
  [ "$framework_count" -gt 0 ] || fail "app contains no signed frameworks"

  while IFS= read -r -d '' dylib_path; do
    [ -x "$dylib_path" ] || fail "dylib executable bit is missing: $dylib_path"
    codesign --verify --strict "$dylib_path" ||
      fail "dylib signature is invalid: $dylib_path"
  done < <(find "$app_path/Frameworks" -type f -name '*.dylib' -print0)
fi

printf 'IPA validation passed: %s\n' "$ipa_path"
