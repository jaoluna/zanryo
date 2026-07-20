#!/usr/bin/env bash

set -euo pipefail

export PATH="/opt/homebrew/opt/rustup/bin:${PATH}"
export MACOSX_DEPLOYMENT_TARGET="14.0"

if [[ -n "${SRCROOT:-}" ]]; then
  repo_root="$(cd "${SRCROOT}/../.." && pwd)"
else
  repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fi
target="aarch64-apple-darwin"
generated_dir="${repo_root}/apps/zanryo-macos/Generated"
library_source="${repo_root}/target/${target}/release/libzanryo_bridge.a"
header_source="${repo_root}/crates/zanryo-bridge/include/zanryo_bridge.h"

if [[ -d "${HOME}/Applications/Xcode.app/Contents/Developer" ]]; then
  export DEVELOPER_DIR="${HOME}/Applications/Xcode.app/Contents/Developer"
fi

if ! rustup target list --installed | grep -qx "${target}"; then
  rustup target add "${target}"
fi

(
  cd "${repo_root}"
  cargo build -p zanryo-bridge --release --target "${target}"
)

mkdir -p "${generated_dir}"

copy_if_changed() {
  local source="$1"
  local destination="$2"

  if [[ -f "${destination}" ]] && cmp -s "${source}" "${destination}"; then
    return
  fi

  cp "${source}" "${destination}"
}

copy_if_changed "${library_source}" "${generated_dir}/libzanryo_bridge.a"
copy_if_changed "${header_source}" "${generated_dir}/zanryo_bridge.h"
