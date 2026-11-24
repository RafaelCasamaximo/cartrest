#!/bin/bash
set -euo pipefail

macos_dir="$(cd -- "$(dirname -- "$0")" && pwd -P)"
project_dir="$(dirname -- "$macos_dir")"
release_dir="$macos_dir/Release"
output_dir="${CARTREST_DIST_DIR:-$project_dir/dist}"

if [[ ${1:-} == -h || ${1:-} == --help ]]; then
  printf 'Usage: %s [X.Y.Z]\n' "$0"
  exit 0
fi

version="${1:-$(/usr/bin/plutil -extract CFBundleShortVersionString raw -o - "$macos_dir/Info.plist")}"
if [[ $# -gt 1 || ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  printf 'Use a version in X.Y.Z format.\n' >&2
  exit 2
fi
identity="${CARTREST_CODESIGN_IDENTITY:--}"
notary_profile="${CARTREST_NOTARY_PROFILE:-}"
if [[ -n "$notary_profile" && "$identity" == - ]]; then
  printf 'Notarization requires a Developer ID Application identity in CARTREST_CODESIGN_IDENTITY.\n' >&2
  exit 2
fi

/bin/mkdir -p "$output_dir"
output_dir="$(cd -- "$output_dir" && pwd -P)"
filename="Cartrest-$version-macOS-universal.dmg"
# Serialize writes for each version so the image and checksum stay paired.
lock_dir="$output_dir/.$filename.lock"
if ! /bin/mkdir "$lock_dir" 2>/dev/null; then
  printf 'The output directory is already reserved for packaging version %s.\n' "$version" >&2
  exit 1
fi
staging_dir=""
cleanup() {
  if [[ -n "$staging_dir" ]]; then
    /bin/rm -rf -- "$staging_dir"
  fi
  /bin/rmdir -- "$lock_dir"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
for path in "$output_dir/$filename" "$output_dir/$filename.sha256"; do
  if [[ -L "$path" || ( -e "$path" && ! -f "$path" ) ]]; then
    printf 'The output path is already occupied: %s\n' "$path" >&2
    exit 1
  fi
done
staging_dir="$(/usr/bin/mktemp -d "$output_dir/.cartrest-release.XXXXXX")"

# Reuse a configured packaging environment, or install the layout tools in a temporary venv.
python="${CARTREST_DMG_PYTHON:-$staging_dir/venv/bin/python}"
if [[ -z "${CARTREST_DMG_PYTHON:-}" ]]; then
  python3 -m venv "$staging_dir/venv"
  "$python" -m pip install --disable-pip-version-check --only-binary :all: -r "$release_dir/requirements.txt"
fi

app="$staging_dir/Cartrest.app"
"$macos_dir/build.sh" --release --version "$version" --output "$app"
/usr/bin/xcrun swift "$release_dir/background.swift" "$staging_dir"

# The layout is written to a read-write image before conversion to read-only UDZO.
dmg="$staging_dir/$filename"
"$python" -m dmgbuild -s "$release_dir/image.py" \
  -D "app=$app" -D "icon=$macos_dir/Cartrest.icns" -D "background=$staging_dir/background.png" \
  Cartrest "$dmg"

if [[ "$identity" != - ]]; then
  /usr/bin/codesign --sign "$identity" --timestamp --identifier local.cartrest.editor.dmg "$dmg"
  /usr/bin/codesign --verify --strict "$dmg"
fi
if [[ -n "$notary_profile" ]]; then
  # Apple checks the distribution container. Staple its ticket before hashing it.
  report="$staging_dir/notarization.json"
  /usr/bin/xcrun notarytool submit "$dmg" --keychain-profile "$notary_profile" --wait --output-format json > "$report"
  if [[ "$(/usr/bin/plutil -extract status raw -o - "$report")" != Accepted ]]; then
    cat "$report" >&2
    exit 1
  fi
  /usr/bin/xcrun stapler staple "$dmg"
  /usr/bin/xcrun stapler validate "$dmg"
fi

/usr/bin/hdiutil verify -quiet "$dmg"
(
  cd -- "$staging_dir"
  /usr/bin/shasum -a 256 "$filename" > "$filename.sha256"
)
# Move the verified image and checksum into place on the same volume as staging.
/bin/mv -f -- "$dmg" "$output_dir/$filename"
/bin/mv -f -- "$staging_dir/$filename.sha256" "$output_dir/$filename.sha256"

printf '\nInstaller built at %s\n' "$output_dir/$filename"
printf 'SHA-256 checksum at %s\n' "$output_dir/$filename.sha256"
