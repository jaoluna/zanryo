#!/usr/bin/env bash

set -euo pipefail

# Xcode runs build phases with a minimal PATH. Cover Homebrew on Apple silicon
# and on Intel, and a rustup.rs install.
export PATH="/opt/homebrew/opt/rustup/bin:/usr/local/opt/rustup/bin:${HOME}/.cargo/bin:${PATH}"
export MACOSX_DEPLOYMENT_TARGET="14.0"

if [[ -n "${SRCROOT:-}" ]]; then
  repo_root="$(cd "${SRCROOT}/../.." && pwd)"
else
  repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fi
generated_dir="${repo_root}/apps/zanryo-macos/Generated"
header_source="${repo_root}/crates/zanryo-bridge/include/zanryo_bridge.h"

if [[ -d "${HOME}/Applications/Xcode.app/Contents/Developer" ]]; then
  export DEVELOPER_DIR="${HOME}/Applications/Xcode.app/Contents/Developer"
fi

# Xcode lists the architectures of the current build in ARCHS. Outside Xcode,
# build for the machine this runs on.
read -r -a archs <<< "${ARCHS:-$(uname -m)}"
if [[ "${#archs[@]}" -eq 0 ]]; then
  printf 'ARCHS names no architecture\n' >&2
  exit 1
fi

# rustup and cargo must resolve the toolchain this repository pins, and the
# libraries are read back from this target directory.
cd "${repo_root}"
target_dir="${repo_root}/target"

installed_targets="$(rustup target list --installed)"
libraries=()
for arch in "${archs[@]}"; do
  case "${arch}" in
    arm64) target="aarch64-apple-darwin" ;;
    x86_64) target="x86_64-apple-darwin" ;;
    *)
      printf 'Unsupported architecture: %s\n' "${arch}" >&2
      exit 1
      ;;
  esac

  if ! grep -qx "${target}" <<< "${installed_targets}"; then
    rustup target add "${target}"
  fi

  cargo build -p zanryo-bridge --release --target "${target}" --target-dir "${target_dir}"
  libraries+=("${target_dir}/${target}/release/libzanryo_bridge.a")
done

if [[ "${#libraries[@]}" -eq 1 ]]; then
  library_source="${libraries[0]}"
else
  library_source="${target_dir}/universal-apple-darwin/release/libzanryo_bridge.a"
  mkdir -p "$(dirname "${library_source}")"
  lipo -create "${libraries[@]}" -output "${library_source}"
fi

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
