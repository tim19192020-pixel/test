#!/usr/bin/env bash
set -euo pipefail

fail() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

show_help() {
  cat <<'EOF'
Build RetroArchTV with the mGBA Multi core and package an unsigned IPA.

Usage:
  ./scripts/build-unsigned-ipa.sh [--prepare-only]

Options:
  --prepare-only  Fetch, patch, and stage metadata without invoking Xcode.
  -h, --help      Show this help.

Environment overrides:
  BUILD_ROOT              Derived files and fetched source location.
  DIST_DIR                Output directory.
  RETROARCH_SOURCE_DIR    Existing pinned RetroArch checkout.
  MGBA_SOURCE_DIR         Existing pinned or fully patched mGBA checkout.
  BUNDLE_ID               Unsigned app bundle identifier.
  TVOS_DEPLOYMENT_TARGET  Minimum tvOS version; default is 13.0.
EOF
}

prepare_only=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    --prepare-only)
      prepare_only=1
      ;;
    -h|--help)
      show_help
      exit 0
      ;;
    *)
      fail "unknown option: $1"
      ;;
  esac
  shift
done

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
kit_root="$(cd "$script_dir/.." && pwd)"
# shellcheck source=../versions.env
source "$kit_root/versions.env"

build_root="${BUILD_ROOT:-$kit_root/.work}"
dist_dir="${DIST_DIR:-$kit_root/dist}"
bundle_id="${BUNDLE_ID:-$BUNDLE_ID_DEFAULT}"
tvos_target="${TVOS_DEPLOYMENT_TARGET:-$TVOS_DEPLOYMENT_TARGET_DEFAULT}"

mkdir -p "$build_root" "$dist_dir"
build_root="$(cd "$build_root" && pwd)"
dist_dir="$(cd "$dist_dir" && pwd)"

case "$build_root" in
  /|"$kit_root")
    fail "BUILD_ROOT must be a dedicated subdirectory, not '$build_root'"
    ;;
esac

source_root="$build_root/sources"
mkdir -p "$source_root"
retroarch_dir="${RETROARCH_SOURCE_DIR:-$source_root/retroarch-$RETROARCH_VERSION}"
mgba_dir="${MGBA_SOURCE_DIR:-$source_root/mgba-multi-$CUSTOM_CORE_VERSION}"

require_command() {
  command -v "$1" >/dev/null 2>&1 || fail "required command not found: $1"
}

for command_name in git zip unzip; do
  require_command "$command_name"
done

prepare_repo() {
  local repository="$1"
  local expected_commit="$2"
  local destination="$3"
  local alternate_commit="${4:-}"
  local current_commit

  if [ ! -d "$destination/.git" ]; then
    if [ -e "$destination" ]; then
      fail "source destination exists but is not a Git checkout: $destination"
    fi
    mkdir -p "$destination"
    git -C "$destination" init --quiet
    git -C "$destination" remote add origin "$repository"
    git -C "$destination" fetch --depth 1 --no-tags origin "$expected_commit"
    git -C "$destination" checkout --quiet --detach FETCH_HEAD
  fi

  current_commit="$(git -C "$destination" rev-parse HEAD)"
  if [ "$current_commit" != "$expected_commit" ] &&
     { [ -z "$alternate_commit" ] || [ "$current_commit" != "$alternate_commit" ]; }; then
    fail "unexpected source commit in $destination: $current_commit"
  fi
}

apply_patch_once() {
  local repository="$1"
  local patch_file="$2"

  if git -C "$repository" apply --check "$patch_file" >/dev/null 2>&1; then
    git -C "$repository" apply "$patch_file"
    printf 'Applied %s\n' "$(basename "$patch_file")"
  elif git -C "$repository" apply --reverse --check "$patch_file" >/dev/null 2>&1; then
    printf 'Already applied: %s\n' "$(basename "$patch_file")"
  else
    fail "patch is neither applicable nor already applied: $patch_file"
  fi
}

prepare_repo "$RETROARCH_REPOSITORY" "$RETROARCH_COMMIT" "$retroarch_dir"
prepare_repo "$MGBA_REPOSITORY" "$MGBA_BASE_COMMIT" "$mgba_dir" "$MGBA_PATCHED_COMMIT"

apply_patch_once "$retroarch_dir" "$kit_root/patches/retroarch-unsigned-frameworks.patch"
apply_patch_once "$mgba_dir" "$kit_root/patches/mgba-multi.patch"

grep -q 'mGBA Multi' \
  "$mgba_dir/src/platform/libretro/mgba_multi_libretro.info" ||
  fail "custom core metadata was not patched into mGBA"
grep -q 'CMAKE_SYSTEM_NAME STREQUAL "tvOS"' "$mgba_dir/CMakeLists.txt" ||
  fail "tvOS CMake support was not patched into mGBA"

asset_zip="$retroarch_dir/pkg/apple/assets.zip"
[ -f "$asset_zip" ] || fail "RetroArch Apple assets archive is missing"

info_tmp_base="${TMPDIR:-$build_root/tmp}"
mkdir -p "$info_tmp_base"
info_tmp="$(mktemp -d "$info_tmp_base/mgba-multi-info.XXXXXX")"
cleanup() {
  if [ -n "${info_tmp:-}" ] && [ -d "$info_tmp" ]; then
    rm -rf -- "$info_tmp"
  fi
}
trap cleanup EXIT

mkdir -p "$info_tmp/info"
cp "$mgba_dir/src/platform/libretro/mgba_multi_libretro.info" \
  "$info_tmp/info/mgba_multi_libretro.info"
(
  cd "$info_tmp"
  zip -q "$asset_zip" info/mgba_multi_libretro.info
)
unzip -l "$asset_zip" | grep -q 'info/mgba_multi_libretro.info' ||
  fail "custom core metadata was not inserted into assets.zip"

rm -rf -- "$info_tmp"
info_tmp=""

if [ "$prepare_only" -eq 1 ]; then
  printf 'Sources prepared successfully.\n'
  printf 'RetroArch: %s\n' "$retroarch_dir"
  printf 'mGBA Multi: %s\n' "$mgba_dir"
  exit 0
fi

[ "$(uname -s)" = "Darwin" ] ||
  fail "the final tvOS build requires macOS with Xcode"

for command_name in cmake xcodebuild xcrun codesign shasum ditto; do
  require_command "$command_name"
done
xcrun --sdk appletvos --show-sdk-path >/dev/null 2>&1 ||
  fail "the Apple TV device SDK is not installed in the selected Xcode"

reset_derived_dir() {
  local target="$1"
  case "$target" in
    "$build_root"/*) ;;
    *) fail "refusing to reset a path outside BUILD_ROOT: $target" ;;
  esac
  rm -rf -- "$target"
  mkdir -p "$target"
}

core_build="$build_root/mgba-tvos-build"
derived_data="$build_root/RetroArchTV-DerivedData"
staging_dir="$build_root/ipa-staging"
reset_derived_dir "$core_build"
reset_derived_dir "$derived_data"
reset_derived_dir "$staging_dir"

cmake -S "$mgba_dir" -B "$core_build" -G Xcode \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_SYSTEM_NAME=tvOS \
  -DCMAKE_OSX_SYSROOT=appletvos \
  -DCMAKE_OSX_ARCHITECTURES=arm64 \
  -DCMAKE_OSX_DEPLOYMENT_TARGET="$tvos_target" \
  -DCMAKE_XCODE_ATTRIBUTE_CODE_SIGNING_ALLOWED=NO \
  -DBUILD_LIBRETRO_MULTI=ON \
  -DBUILD_LIBRETRO=OFF \
  -DBUILD_QT=OFF \
  -DBUILD_SDL=OFF \
  -DBUILD_GL=OFF \
  -DBUILD_GLES2=OFF \
  -DBUILD_GLES3=OFF \
  -DENABLE_SCRIPTING=OFF \
  -DENABLE_DEBUGGERS=OFF \
  -DDISABLE_DEPS=ON \
  -DSKIP_LIBRARY=ON \
  -DUSE_FFMPEG=OFF \
  -DUSE_LZMA=OFF \
  -DUSE_MINIZIP=OFF \
  -DUSE_LIBZIP=OFF \
  -DUSE_ZLIB=OFF \
  -DUSE_PNG=OFF \
  -DUSE_SQLITE3=OFF \
  -DUSE_DISCORD_RPC=OFF \
  -DUSE_EDITLINE=OFF

cmake --build "$core_build" --config Release \
  --target mgba_multi_libretro --parallel

shopt -s nullglob
core_dylibs=("$core_build"/Release/mgba_multi_libretro.dylib)
if [ "${#core_dylibs[@]}" -ne 1 ]; then
  core_dylibs=()
  while IFS= read -r core_candidate; do
    core_dylibs+=("$core_candidate")
  done < <(find "$core_build" -type f -name mgba_multi_libretro.dylib -print)
fi
shopt -u nullglob

[ "${#core_dylibs[@]}" -eq 1 ] ||
  fail "expected exactly one mGBA Multi tvOS dylib"
core_dylib="${core_dylibs[0]}"

core_archs="$(xcrun lipo "$core_dylib" -archs)" ||
  fail "could not inspect the custom core architectures"
case " $core_archs " in
  *" arm64 "*) ;;
  *) fail "custom core is not an arm64 binary (architectures: ${core_archs:-none})" ;;
esac
core_build_info="$(xcrun vtool -show-build "$core_dylib")" ||
  fail "could not inspect the custom core platform metadata"
grep -qi 'platform.*TVOS' <<<"$core_build_info" ||
  fail "custom core is not marked for the tvOS device platform"

module_dir="$retroarch_dir/pkg/apple/tvOS/modules"
mkdir -p "$module_dir"
module_dylib="$module_dir/mgba_multi_libretro_tvos.dylib"
rm -f -- "$module_dylib"
cp "$core_dylib" "$module_dylib"

(
  cd "$retroarch_dir/pkg/apple"
  EXPANDED_CODE_SIGN_IDENTITY="-" xcodebuild \
    -project RetroArch_iOS13.xcodeproj \
    -scheme "RetroArch tvOS Release" \
    -configuration Release \
    -sdk appletvos \
    -destination 'generic/platform=tvOS' \
    -derivedDataPath "$derived_data" \
    APPSTORE_BUILD= \
    ARCHS=arm64 \
    ONLY_ACTIVE_ARCH=NO \
    TVOS_DEPLOYMENT_TARGET="$tvos_target" \
    TVOS_BUNDLE_IDENTIFIER="$bundle_id" \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGN_IDENTITY=- \
    CODE_SIGN_ENTITLEMENTS= \
    DEVELOPMENT_TEAM= \
    PROVISIONING_PROFILE_SPECIFIER= \
    ENABLE_USER_SCRIPT_SANDBOXING=NO \
    VALIDATE_PRODUCT=NO \
    COMPILER_INDEX_STORE_ENABLE=NO \
    build
)

shopt -s nullglob
apps=("$derived_data"/Build/Products/Release-appletvos/*.app)
shopt -u nullglob
[ "${#apps[@]}" -eq 1 ] ||
  fail "expected exactly one RetroArchTV app product"
app_path="${apps[0]}"

core_framework="$app_path/Frameworks/mgba.multi.libretro.framework/mgba.multi.libretro"
[ -f "$core_framework" ] ||
  fail "mGBA Multi framework is missing from the app bundle"
[ -f "$app_path/assets.zip" ] ||
  fail "assets.zip is missing from the app bundle"
unzip -l "$app_path/assets.zip" | grep -q 'info/mgba_multi_libretro.info' ||
  fail "mGBA Multi metadata is missing from the app bundle"

mkdir -p "$staging_dir/Payload"
ditto "$app_path" "$staging_dir/Payload/RetroArchTV.app"

ipa_name="RetroArchTV-mGBA-Multi-$RETROARCH_VERSION-core-$CUSTOM_CORE_VERSION-unsigned.ipa"
ipa_path="$dist_dir/$ipa_name"
rm -f -- "$ipa_path" "$dist_dir/SHA256SUMS.txt" "$dist_dir/BUILD-MANIFEST.txt"
(
  cd "$staging_dir"
  COPYFILE_DISABLE=1 zip -qry "$ipa_path" Payload
)

{
  printf 'kit_version=%s\n' "$KIT_VERSION"
  printf 'built_utc=%s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  printf 'retroarch_version=%s\n' "$RETROARCH_VERSION"
  printf 'retroarch_commit=%s\n' "$RETROARCH_COMMIT"
  printf 'mgba_base_commit=%s\n' "$MGBA_BASE_COMMIT"
  printf 'mgba_patch_sha256=%s\n' \
    "$(shasum -a 256 "$kit_root/patches/mgba-multi.patch" | awk '{print $1}')"
  printf 'custom_core_version=%s\n' "$CUSTOM_CORE_VERSION"
  printf 'bundle_id=%s\n' "$bundle_id"
  printf 'tvos_deployment_target=%s\n' "$tvos_target"
  printf 'tvos_sdk=%s\n' "$(xcrun --sdk appletvos --show-sdk-version)"
  xcodebuild -version | sed 's/^/xcode=/'
} > "$dist_dir/BUILD-MANIFEST.txt"

(
  cd "$dist_dir"
  shasum -a 256 "$ipa_name" > SHA256SUMS.txt
)

"$kit_root/scripts/validate-ipa.sh" "$ipa_path"

printf '\nBuild complete:\n%s\n' "$ipa_path"
printf 'This IPA has no distribution signature; sign it with your own Apple ID/team before installation.\n'
