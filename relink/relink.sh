#!/usr/bin/env bash
# Replaces one LGPL-covered native library inside a released MANUL app
# bundle (.aab) with a rebuilt version, and repackages the result into a
# self-signed, installable universal APK.
#
# This script does NOT compile anything — it only unpacks, edits, repacks
# and re-signs. Build your replacement .so files first with
# ../build-libraries/build.sh (or your own build of the same project).
#
# Usage:
#   relink.sh --aab <released.aab> --library <name> \
#             (--libs-dir <dir> | --lib <file.so> --abi <abi>) \
#             --keystore <keystore.jks> --ks-pass <pass> \
#             --key-alias <alias> --key-pass <pass> \
#             --bundletool <bundletool-all-X.Y.Z.jar> \
#             --output <relinked-universal.apk>
#
# --library selects which of the four LGPL libraries you rebuilt, and is
# used only to validate the filenames you provide match what that library
# actually produces (fail fast on a typo, rather than silently no-op).
# One of: fluidsynth | libsndfile | libinstpatch | glib
#
# --libs-dir must contain one subdirectory per ABI you have a rebuilt
# library for, named exactly as Android names them (arm64-v8a,
# armeabi-v7a, x86, x86_64), each holding the replacement .so file(s)
# under their original filename. You do not need all four ABIs — only the
# ones you rebuilt; the others are left untouched. --lib/--abi is a
# shorthand for a single file/ABI instead of a directory.
#
# See INSTRUCTIONS.md for the full walkthrough, including where to get
# bundletool and how to create a keystore if you don't have one.
set -euo pipefail

SCRIPT_NAME="$(basename "$0")"

die() {
  echo "ERROR: $*" >&2
  exit 1
}

usage() {
  sed -n '2,29p' "$0" | sed 's/^# \{0,1\}//'
  exit "${1:-1}"
}

AAB=""
LIBRARY=""
LIBS_DIR=""
SINGLE_LIB=""
SINGLE_ABI=""
KEYSTORE=""
KS_PASS=""
KEY_ALIAS=""
KEY_PASS=""
BUNDLETOOL=""
OUTPUT=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --aab) AAB="$2"; shift 2 ;;
    --library) LIBRARY="$2"; shift 2 ;;
    --libs-dir) LIBS_DIR="$2"; shift 2 ;;
    --lib) SINGLE_LIB="$2"; shift 2 ;;
    --abi) SINGLE_ABI="$2"; shift 2 ;;
    --keystore) KEYSTORE="$2"; shift 2 ;;
    --ks-pass) KS_PASS="$2"; shift 2 ;;
    --key-alias) KEY_ALIAS="$2"; shift 2 ;;
    --key-pass) KEY_PASS="$2"; shift 2 ;;
    --bundletool) BUNDLETOOL="$2"; shift 2 ;;
    --output) OUTPUT="$2"; shift 2 ;;
    -h|--help) usage 0 ;;
    *) die "unknown argument: $1 (see --help)" ;;
  esac
done

# --- Validate required inputs -------------------------------------------
[[ -n "${AAB}" ]] || die "--aab is required"
[[ -f "${AAB}" ]] || die "AAB not found: ${AAB}"
[[ -n "${LIBRARY}" ]] || die "--library is required (fluidsynth|libsndfile|libinstpatch|glib)"
[[ -n "${KEYSTORE}" ]] || die "--keystore is required"
[[ -f "${KEYSTORE}" ]] || die "keystore not found: ${KEYSTORE}"
[[ -n "${KS_PASS}" ]] || die "--ks-pass is required"
[[ -n "${KEY_ALIAS}" ]] || die "--key-alias is required"
[[ -n "${KEY_PASS}" ]] || die "--key-pass is required"
[[ -n "${OUTPUT}" ]] || die "--output is required"

if [[ -n "${LIBS_DIR}" ]]; then
  [[ -z "${SINGLE_LIB}" && -z "${SINGLE_ABI}" ]] || die "pass either --libs-dir or --lib/--abi, not both"
  [[ -d "${LIBS_DIR}" ]] || die "--libs-dir not found: ${LIBS_DIR}"
elif [[ -n "${SINGLE_LIB}" || -n "${SINGLE_ABI}" ]]; then
  [[ -n "${SINGLE_LIB}" && -n "${SINGLE_ABI}" ]] || die "--lib and --abi must be given together"
  [[ -f "${SINGLE_LIB}" ]] || die "--lib file not found: ${SINGLE_LIB}"
else
  die "one of --libs-dir or --lib/--abi is required"
fi

# --- Validate tools are present ------------------------------------------
for tool in java unzip zip; do
  command -v "${tool}" >/dev/null 2>&1 || die "required tool not found on PATH: ${tool} (see INSTRUCTIONS.md for what to install)"
done

if [[ -z "${BUNDLETOOL}" ]]; then
  # Look for it where INSTRUCTIONS.md tells the reader to put it, before
  # giving up.
  for candidate in "${BUNDLETOOL_JAR:-}" "$(dirname "$0")/bundletool-all-1.18.3.jar" "./bundletool-all-1.18.3.jar"; do
    if [[ -n "${candidate}" && -f "${candidate}" ]]; then
      BUNDLETOOL="${candidate}"
      break
    fi
  done
fi
[[ -n "${BUNDLETOOL}" ]] || die "bundletool jar not found. Pass --bundletool <path>, set \$BUNDLETOOL_JAR, or download bundletool-all-1.18.3.jar next to this script (see INSTRUCTIONS.md)."
[[ -f "${BUNDLETOOL}" ]] || die "bundletool jar not found at: ${BUNDLETOOL}"

# --- Known ABIs and per-library filenames --------------------------------
KNOWN_ABIS=(arm64-v8a armeabi-v7a x86 x86_64)
is_known_abi() {
  local abi="$1"
  for a in "${KNOWN_ABIS[@]}"; do [[ "${a}" == "${abi}" ]] && return 0; done
  return 1
}

case "${LIBRARY}" in
  fluidsynth)   EXPECTED_FILES=(libfluidsynth.so) ;;
  libsndfile)   EXPECTED_FILES=(libsndfile.so) ;;
  libinstpatch) EXPECTED_FILES=(libinstpatch-1.0.so) ;;
  glib)         EXPECTED_FILES=(libglib-2.0.so libgobject-2.0.so libgio-2.0.so libgmodule-2.0.so libgthread-2.0.so) ;;
  *) die "--library must be one of: fluidsynth, libsndfile, libinstpatch, glib (got: ${LIBRARY})" ;;
esac

is_expected_file() {
  local name="$1"
  local expected
  for expected in "${EXPECTED_FILES[@]}"; do [[ "${expected}" == "${name}" ]] && return 0; done
  return 1
}

# --- Build the list of (abi, file) replacements to apply -----------------
declare -a REPLACE_ABI=()
declare -a REPLACE_FILE=()

if [[ -n "${LIBS_DIR}" ]]; then
  for abi_dir in "${LIBS_DIR}"/*/; do
    [[ -d "${abi_dir}" ]] || continue
    abi="$(basename "${abi_dir}")"
    is_known_abi "${abi}" || die "unrecognized ABI directory name: ${abi} (expected one of: ${KNOWN_ABIS[*]})"
    for f in "${abi_dir}"*.so; do
      [[ -e "${f}" ]] || continue
      base="$(basename "${f}")"
      # build-libraries/build.sh always builds and collects every library
      # (plus non-LGPL runtime deps) into out/<abi>/ together, not just the
      # one you changed — so --libs-dir routinely contains unrelated .so
      # files. Only the ones matching --library are relevant here; the rest
      # are silently skipped rather than treated as an error.
      is_expected_file "${base}" || continue
      REPLACE_ABI+=("${abi}")
      REPLACE_FILE+=("${f}")
    done
  done
  [[ "${#REPLACE_FILE[@]}" -gt 0 ]] || die "no binaries belonging to '${LIBRARY}' (${EXPECTED_FILES[*]}) found under ${LIBS_DIR}/<abi>/ — wrong --library, or wrong --libs-dir?"
else
  is_known_abi "${SINGLE_ABI}" || die "unrecognized --abi: ${SINGLE_ABI} (expected one of: ${KNOWN_ABIS[*]})"
  base="$(basename "${SINGLE_LIB}")"
  is_expected_file "${base}" || die "${SINGLE_LIB}: '${base}' is not one of ${LIBRARY}'s binaries (${EXPECTED_FILES[*]}) — wrong --library, or wrong file?"
  REPLACE_ABI+=("${SINGLE_ABI}")
  REPLACE_FILE+=("${SINGLE_LIB}")
fi

# --- Work in a scratch directory, clean up on exit or failure ------------
WORKDIR="$(mktemp -d)"
cleanup() { rm -rf "${WORKDIR}"; }
trap cleanup EXIT

BUNDLE_DIR="${WORKDIR}/bundle"
mkdir -p "${BUNDLE_DIR}"

echo "Unpacking ${AAB}..."
unzip -q "${AAB}" -d "${BUNDLE_DIR}" || die "failed to unpack AAB — is it a valid app bundle?"

for i in "${!REPLACE_FILE[@]}"; do
  abi="${REPLACE_ABI[${i}]}"
  file="${REPLACE_FILE[${i}]}"
  base="$(basename "${file}")"
  target="${BUNDLE_DIR}/base/lib/${abi}/${base}"
  [[ -f "${target}" ]] || die "bundle has no ${target} — this AAB does not ship ${base} for ${abi}, or the bundle layout doesn't match what this script expects (base/lib/<abi>/)"
  echo "Replacing base/lib/${abi}/${base}"
  cp "${file}" "${target}"
done

RELINKED_AAB="${WORKDIR}/relinked.aab"
echo "Repacking bundle..."
( cd "${BUNDLE_DIR}" && zip -q -X -D -r "${RELINKED_AAB}" . )

APKS="${WORKDIR}/relinked.apks"
echo "Running bundletool (universal, self-signed)..."
java -jar "${BUNDLETOOL}" build-apks \
  --bundle="${RELINKED_AAB}" \
  --output="${APKS}" \
  --mode=universal \
  --ks="${KEYSTORE}" \
  --ks-pass="pass:${KS_PASS}" \
  --ks-key-alias="${KEY_ALIAS}" \
  --key-pass="pass:${KEY_PASS}" \
  --overwrite \
  || die "bundletool failed — check the keystore/alias/passwords, and that this bundletool version matches INSTRUCTIONS.md"

mkdir -p "$(dirname "${OUTPUT}")"
unzip -p "${APKS}" universal.apk > "${OUTPUT}" \
  || die "bundletool did not produce universal.apk inside ${APKS}"

echo ""
echo "Done: ${OUTPUT}"
echo ""
echo "This APK is signed with your own key, not MANUL's, but keeps MANUL's"
echo "package name — Android will refuse to install it over an existing"
echo "Play Store copy (different signing key, same package). If MANUL is"
echo "already installed, uninstall it first:"
echo "  adb uninstall com.manulscore"
echo "  adb install \"${OUTPUT}\""
