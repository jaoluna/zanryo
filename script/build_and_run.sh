#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mode="${1:-run}"
case "$mode" in
  run|--verify|--build-only) ;;
  *) printf 'Usage: %s [run|--verify|--build-only]\n' "$0" >&2; exit 2 ;;
esac

# --build-only never stops the installed app. Tests use the guarded XCTest host.
if [[ "$mode" != --build-only ]]; then
  /usr/bin/pkill -x Zanryo || [[ $? == 1 ]]
fi
if [[ -z "${DEVELOPER_DIR:-}" && -d "${HOME}/Applications/Xcode.app/Contents/Developer" ]]; then
  export DEVELOPER_DIR="${HOME}/Applications/Xcode.app/Contents/Developer"
fi
derived="${ZANRYO_DERIVED_DATA:-${root}/.build/macos}"
xcodegen generate --spec "${root}/apps/zanryo-macos/project.yml"
xcodebuild -project "${root}/apps/zanryo-macos/Zanryo.xcodeproj" \
  -scheme Zanryo -configuration Release -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath "$derived" build
[[ "$mode" == --build-only ]] && exit 0
app="${derived}/Build/Products/Release/Zanryo.app"
/usr/bin/open -n "$app"
if [[ "$mode" == --verify ]]; then
  for _ in {1..10}; do
    /usr/bin/pgrep -f "^${app}/Contents/MacOS/Zanryo$" >/dev/null && exit 0
    sleep 1
  done
  printf 'Zanryo did not remain running at %s\n' "$app" >&2
  exit 1
fi
