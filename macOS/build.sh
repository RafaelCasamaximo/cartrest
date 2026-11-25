#!/bin/bash
set -euo pipefail

macos_dir="$(cd -- "$(dirname -- "$0")" && pwd -P)"
project_dir="$(dirname -- "$macos_dir")"
output="$project_dir/Cartrest.app"
architectures=("$(/usr/bin/uname -m)")
version=""

usage() {
  printf 'Usage: %s [--release] [--version X.Y.Z] [--output PATH/Cartrest.app]\n' "$0"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --release)
      architectures=(arm64 x86_64)
      shift
      ;;
    --version|--output)
      if [[ $# -lt 2 || -z "$2" || "$2" == --* ]]; then
        usage >&2
        exit 2
      fi
      if [[ "$1" == --version ]]; then
        version="$2"
      else
        output="$2"
      fi
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      usage >&2
      exit 2
      ;;
  esac
done

if [[ -n "$version" && ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  printf 'Use a version in X.Y.Z format.\n' >&2
  exit 2
fi
if [[ "$(basename -- "$output")" != Cartrest.app || -L "$output" ]]; then
  printf 'The output path must point to Cartrest.app.\n' >&2
  exit 2
fi
if [[ ! -f "$macos_dir/Cartrest/CartrestApp.swift" ]]; then
  printf 'The app entry point is missing from %s.\n' "$macos_dir/Cartrest/CartrestApp.swift" >&2
  exit 1
fi

/bin/mkdir -p "$(dirname -- "$output")"
output_dir="$(cd -- "$(dirname -- "$output")" && pwd -P)"
output="$output_dir/Cartrest.app"

# Stage on the same volume as the output so the final rename is atomic.
staging_dir="$(/usr/bin/mktemp -d "$output_dir/.cartrest-build.XXXXXX")"
trap '/bin/rm -rf -- "$staging_dir"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

app="$staging_dir/Cartrest.app"
contents="$app/Contents"
resources="$contents/Resources"
plist="$contents/Info.plist"
/bin/mkdir -p "$contents/MacOS" "$resources"
/usr/bin/install -m 644 "$macos_dir/Info.plist" "$plist"
/usr/bin/install -m 644 "$macos_dir/Cartrest.icns" "$resources/Cartrest.icns"
# Discover profiles by filename. The editor builds their meshes from the JSON recipes.
/bin/mkdir -p "$resources/Consoles" "$resources/SampleArtwork"
for profile in "$project_dir"/consoles/*.json; do
  if [[ "$(basename -- "$profile")" != profile.schema.json ]]; then
    /usr/bin/install -m 644 "$profile" "$resources/Consoles/"
  fi
done
# The optional starter image is also available in the examples.
/usr/bin/install -m 644 "$project_dir/examples/artwork/Mario Kart DS.png" "$resources/SampleArtwork/"
if [[ -n "$version" ]]; then
  /usr/bin/plutil -replace CFBundleShortVersionString -string "$version" "$plist"
  /usr/bin/plutil -replace CFBundleVersion -string "$version" "$plist"
fi
/usr/bin/plutil -lint "$plist" >/dev/null

if [[ -e "$output" ]]; then
  identifier="$(/usr/bin/plutil -extract CFBundleIdentifier raw -o - "$plist")"
  existing_identifier="$(/usr/bin/plutil -extract CFBundleIdentifier raw -o - "$output/Contents/Info.plist" 2>/dev/null || true)"
  if [[ "$existing_identifier" != "$identifier" ]]; then
    printf 'Another item already exists at %s. Choose a different output directory.\n' "$output" >&2
    exit 1
  fi
fi

minimum_version="$(/usr/bin/plutil -extract LSMinimumSystemVersion raw -o - "$plist")"
sdk="$(/usr/bin/xcrun --sdk macosx --show-sdk-path)"
executables=()
for architecture in "${architectures[@]}"; do
  executable="$staging_dir/Cartrest-$architecture"
  /usr/bin/xcrun --sdk macosx swiftc \
    -target "${architecture}-apple-macos${minimum_version}" -sdk "$sdk" \
    -parse-as-library -O -whole-module-optimization "$macos_dir"/Cartrest/*.swift \
    -o "$executable"
  executables+=("$executable")
done

# Each slice is compiled for its own target before lipo combines the binaries.
binary="$contents/MacOS/Cartrest"
if [[ ${#executables[@]} -eq 1 ]]; then
  /bin/mv "${executables[0]}" "$binary"
else
  /usr/bin/xcrun lipo -create "${executables[@]}" -output "$binary"
fi
for architecture in "${architectures[@]}"; do
  /usr/bin/xcrun lipo "$binary" -verify_arch "$architecture"
done

# Sign the final bundle. Developer ID signing also enables the hardened runtime.
identity="${CARTREST_CODESIGN_IDENTITY:--}"
if [[ "$identity" == - ]]; then
  /usr/bin/codesign --force --sign - --timestamp=none "$app"
else
  /usr/bin/codesign --force --sign "$identity" --options runtime --timestamp "$app"
fi
/usr/bin/codesign --verify --strict --all-architectures "$app"

# RENAME_SWAP keeps the old version available until the new one is built and signed.
/usr/bin/xcrun swift - "$app" "$output" <<'SWIFT'
import Darwin

let source = CommandLine.arguments[1]
let destination = CommandLine.arguments[2]
if renamex_np(source, destination, UInt32(RENAME_EXCL)) != 0 {
    guard errno == EEXIST, renamex_np(source, destination, UInt32(RENAME_SWAP)) == 0 else {
        perror("Could not replace Cartrest.app")
        exit(EXIT_FAILURE)
    }
}
SWIFT

printf 'App built at %s\n' "$output"
