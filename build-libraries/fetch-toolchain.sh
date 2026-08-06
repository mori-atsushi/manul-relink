#!/usr/bin/env bash
# Downloads and verifies the pinned Android NDK and CMake into ./toolchain/.
# Run this once before build.sh (or let the Dockerfile run it for you).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=versions.sh
source "${SCRIPT_DIR}/versions.sh"

TOOLCHAIN_DIR="${SCRIPT_DIR}/toolchain"
mkdir -p "${TOOLCHAIN_DIR}"
cd "${TOOLCHAIN_DIR}"

verify_sha256() {
  local file="$1" expected="$2"
  local actual
  actual="$(sha256sum "${file}" | awk '{print $1}')"
  if [[ "${actual}" != "${expected}" ]]; then
    echo "ERROR: checksum mismatch for ${file}" >&2
    echo "  expected: ${expected}" >&2
    echo "  actual:   ${actual}" >&2
    exit 1
  fi
}

verify_sha1() {
  local file="$1" expected="$2"
  local actual
  actual="$(sha1sum "${file}" | awk '{print $1}')"
  if [[ "${actual}" != "${expected}" ]]; then
    echo "ERROR: checksum mismatch for ${file}" >&2
    echo "  expected: ${expected}" >&2
    echo "  actual:   ${actual}" >&2
    exit 1
  fi
}

if [[ ! -d "android-ndk-${NDK_VERSION}" ]]; then
  echo "Downloading Android NDK ${NDK_VERSION} (side-by-side 27.2.12479018)..."
  curl -fL -o ndk.zip "${NDK_URL}"
  verify_sha1 ndk.zip "${NDK_SHA1}"
  unzip -q ndk.zip
  rm ndk.zip
else
  echo "NDK already present at ${TOOLCHAIN_DIR}/android-ndk-${NDK_VERSION}, skipping download."
fi

if [[ ! -d "cmake-${CMAKE_VERSION}-linux-x86_64" ]]; then
  echo "Downloading CMake ${CMAKE_VERSION}..."
  curl -fL -o cmake.tar.gz "${CMAKE_URL}"
  verify_sha256 cmake.tar.gz "${CMAKE_SHA256}"
  tar xf cmake.tar.gz
  rm cmake.tar.gz
else
  echo "CMake already present at ${TOOLCHAIN_DIR}/cmake-${CMAKE_VERSION}-linux-x86_64, skipping download."
fi

echo "Toolchain ready:"
echo "  NDK:   ${TOOLCHAIN_DIR}/android-ndk-${NDK_VERSION}"
echo "  CMake: ${TOOLCHAIN_DIR}/cmake-${CMAKE_VERSION}-linux-x86_64/bin/cmake"
