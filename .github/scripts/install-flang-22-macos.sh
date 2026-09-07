#!/bin/bash
set -euo pipefail

# flang 23.1.0 miscompiles fortsh at -O1 and above on macOS ARM64. Keep the
# macOS release gates on the last known-good compiler until that regression is
# resolved upstream. The bottle and checksum come from Homebrew/core commit
# 84890827fdee556e5cf74cf6c34be34cf8686eed.
readonly flang_version="22.1.8"
readonly bottle_sha256="61ad234cf8b2d1c97186a5e41f96972d698528c5e4e6a5a5944190fc895959fb"
readonly bottle_url="https://ghcr.io/v2/homebrew/core/flang/blobs/sha256:${bottle_sha256}"
readonly bottle_path="${RUNNER_TEMP}/flang-${flang_version}.bottle.tar.gz"

export HOMEBREW_NO_AUTO_UPDATE=1
brew install coreutils bash llvm@22

readonly brew_prefix="$(brew --prefix)"
readonly brew_cellar="$(brew --cellar)"
readonly flang_keg="${brew_cellar}/flang/${flang_version}"
readonly flang_opt_link="${brew_prefix}/opt/flang"
readonly llvm_compat_link="${brew_prefix}/opt/llvm"

if [[ -e "${flang_keg}" || -L "${flang_keg}" ]]; then
  echo "Refusing to overwrite existing flang keg: ${flang_keg}" >&2
  exit 1
fi

registry_token="$({ curl -fsSL \
  'https://ghcr.io/token?scope=repository%3Ahomebrew%2Fcore%2Fflang%3Apull&service=ghcr.io'; } | \
  python3 -c 'import json, sys; print(json.load(sys.stdin)["token"])')"
curl -fL --retry 3 --retry-all-errors \
  -H "Authorization: Bearer ${registry_token}" \
  -o "${bottle_path}" "${bottle_url}"
unset registry_token

echo "${bottle_sha256}  ${bottle_path}" | shasum -a 256 -c -
tar -xzf "${bottle_path}" -C "${brew_cellar}"

# Homebrew bottles contain relocatable path placeholders. Apply the same keg
# relocation Homebrew performs during a normal bottle installation.
brew ruby -e \
  'require "keg"; Keg.new(Pathname(ARGV.fetch(0))).replace_placeholders_with_locations(nil)' \
  "${flang_keg}"

# The 22.1.8 flang bottle names the unversioned LLVM opt path. This runner only
# installs the ABI-matching versioned keg, so make that expected path explicit.
if [[ -e "${llvm_compat_link}" || -L "${llvm_compat_link}" ]]; then
  echo "Refusing to replace existing LLVM compatibility path: ${llvm_compat_link}" >&2
  exit 1
fi
ln -s "${brew_prefix}/opt/llvm@22" "${llvm_compat_link}"

# Linked programs record the stable Homebrew opt path for the flang runtime.
if [[ -e "${flang_opt_link}" || -L "${flang_opt_link}" ]]; then
  echo "Refusing to replace existing flang opt path: ${flang_opt_link}" >&2
  exit 1
fi
ln -s "${flang_keg}" "${flang_opt_link}"
test -r "${flang_opt_link}/lib/clang/22/lib/darwin/libflang_rt.runtime.dylib"

echo "${flang_keg}/bin" >> "${GITHUB_PATH}"
"${flang_keg}/bin/flang-new" --version
