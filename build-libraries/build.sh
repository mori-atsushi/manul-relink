#!/usr/bin/env bash
# Cross-compiles FluidSynth 2.4.7 and everything it needs for Android
# (GLib, libsndfile, libinstpatch, plus the non-LGPL runtime deps FLAC,
# Ogg, Vorbis, Opus, PCRE, Oboe) for all four ABIs MANUL ships.
#
# This is a line-by-line shell translation of FluidSynth's own Azure
# Pipelines recipe at tag v2.4.7:
#   https://github.com/FluidSynth/fluidsynth/blob/v2.4.7/.azure/azure-pipelines-android.yml
#   https://github.com/FluidSynth/fluidsynth/blob/v2.4.7/.azure/cmake-android.yml
# Each block below is commented with the step name it corresponds to in
# that file, so you can diff this script against the original if FluidSynth
# changes its recipe in a later version. Azure runs one job per ABI in
# parallel (a build matrix); this script runs the same steps in a loop.
#
# Run via the Dockerfile in this directory, or directly on an
# Ubuntu 22.04 x86_64 host with the apt packages listed in the Dockerfile
# already installed and fetch-toolchain.sh already run.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=versions.sh
source "${SCRIPT_DIR}/versions.sh"

WORK="${SCRIPT_DIR}/work"
OUT="${SCRIPT_DIR}/out"
NDK="${SCRIPT_DIR}/toolchain/android-ndk-${NDK_VERSION}"
CMAKE_BIN="${SCRIPT_DIR}/toolchain/cmake-${CMAKE_VERSION}-linux-x86_64/bin/cmake"
# LOCAL VERIFICATION ONLY (macOS host, not the Linux CI this recipe targets):
# the pinned Linux binary can't run here. A host-installed cmake seemed like
# the obvious substitute, but a modern cmake (tested: 4.4.2 via Homebrew)
# rejects several vendored libraries' old cmake_minimum_required()/
# cmake_policy(SET ... OLD) calls (PCRE 8.45 hits CMP0026, removed outright
# in CMake >= 4). Use the same 3.22.1 release, just the macOS build, instead.
MACOS_CMAKE_BIN="${SCRIPT_DIR}/toolchain/cmake-${CMAKE_VERSION}-macos10.10-universal/CMake.app/Contents/bin/cmake"
if [[ ! -x "${CMAKE_BIN}" && -x "${MACOS_CMAKE_BIN}" ]]; then
  CMAKE_BIN="${MACOS_CMAKE_BIN}"
fi

if [[ ! -x "${CMAKE_BIN}" || ! -d "${NDK}" ]]; then
  echo "ERROR: toolchain not found. Run fetch-toolchain.sh first." >&2
  exit 1
fi

mkdir -p "${WORK}" "${OUT}"

# --- 'Download Dependencies' -------------------------------------------
# Fetched once, shared across all four ABI builds (the source is
# architecture-independent; only the compiled output differs).
SRC="${WORK}/src"
mkdir -p "${SRC}"
cd "${SRC}"

fetch() {
  local url="$1" out="$2" sha256="$3"
  if [[ -f "${out}" ]]; then
    # Trust whatever is already here without re-checking its checksum: the
    # checksum guards against a corrupted/tampered *download*, not against
    # your own edit for step 2's "make your changes" — replace ${out} with
    # your modified archive (same filename) before running this script, and
    # it's used as-is.
    echo "  ${out} already present, using it as-is"
    return
  fi
  echo "  downloading ${out}..."
  curl -fL -o "${out}" "${url}"
  local actual
  actual="$(sha256sum "${out}" | awk '{print $1}')"
  if [[ "${actual}" != "${sha256}" ]]; then
    echo "ERROR: checksum mismatch for ${out}" >&2
    echo "  expected: ${sha256}" >&2
    echo "  actual:   ${actual}" >&2
    exit 1
  fi
}

echo "Fetching sources..."
fetch "${ICONV_URL}"      "libiconv-${ICONV_VERSION}.tar.gz"        "${ICONV_SHA256}"
fetch "${FFI_URL}"        "libffi-${FFI_COMMIT}.tar.gz"             "${FFI_SHA256}"
fetch "${GETTEXT_URL}"    "gettext-${GETTEXT_VERSION}.tar.gz"       "${GETTEXT_SHA256}"
fetch "${GLIB_SOURCE_URL}" "glib-${GLIB_VERSION}.${GLIB_EXTRAVERSION}.tar.xz" "${GLIB_SOURCE_SHA256}"
fetch "${OBOE_URL}"       "oboe-${OBOE_VERSION}.tar.gz"             "${OBOE_SHA256}"
fetch "${SNDFILE_SOURCE_URL}" "libsndfile-${SNDFILE_VERSION}.tar.xz" "${SNDFILE_SOURCE_SHA256}"
fetch "${INSTPATCH_SOURCE_URL}" "libinstpatch-${INSTPATCH_VERSION}.tar.gz" "${INSTPATCH_SOURCE_SHA256}"
fetch "${VORBIS_URL}"     "libvorbis-${VORBIS_VERSION}.tar.gz"      "${VORBIS_SHA256}"
fetch "${OGG_URL}"        "libogg-${OGG_VERSION}.tar.gz"            "${OGG_SHA256}"
fetch "${FLAC_URL}"       "flac-${FLAC_VERSION}.tar.gz"             "${FLAC_SHA256}"
fetch "${OPUS_URL}"       "opus-${OPUS_VERSION}.tar.gz"             "${OPUS_SHA256}"
fetch "${PCRE_URL}"       "pcre-${PCRE_VERSION}.tar.bz2"            "${PCRE_SHA256}"
fetch "${FLUIDSYNTH_SOURCE_URL}" "fluidsynth-${FLUIDSYNTH_VERSION}.tar.gz" "${FLUIDSYNTH_SOURCE_SHA256}"

# cmake_invoke <sourceDir> <buildDir-relative-to-sourceDir> <extra cmake args...>
# Translation of the shared 'cmake-android.yml' template's cmake invocation.
cmake_invoke() {
  local src_dir="$1"; shift
  local build_dir="$1"; shift
  mkdir -p "${build_dir}"
  (
    cd "${build_dir}"
    "${CMAKE_BIN}" -G "Unix Makefiles" \
      -DCMAKE_MAKE_PROGRAM=make \
      -DCMAKE_TOOLCHAIN_FILE="${NDK}/build/cmake/android.toolchain.cmake" \
      -DCMAKE_BUILD_TYPE=RelWithDebInfo \
      -DANDROID_NATIVE_API_LEVEL="${ANDROID_API}" \
      -DANDROID_ABI="${ANDROID_ABI_CMAKE}" \
      -DANDROID_TOOLCHAIN="${CC}" \
      -DANDROID_NDK="${NDK}" \
      -DANDROID_COMPILER_FLAGS="${CFLAGS// /;}" \
      -DANDROID_LINKER_FLAGS="${LDFLAGS// /;}" \
      -DANDROID_STL="c++_shared" \
      -DCMAKE_REQUIRED_FLAGS="${CFLAGS}" \
      -DCMAKE_REQUIRED_LINK_OPTIONS="${LDFLAGS// /;}" \
      -DCMAKE_INSTALL_PREFIX="${PREFIX}" \
      -DCMAKE_STAGING_PREFIX="${PREFIX}" \
      -DCMAKE_VERBOSE_MAKEFILE=1 \
      -DBUILD_SHARED_LIBS=1 \
      -DLIB_SUFFIX= \
      -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
      "$@" \
      "${src_dir}"
    make -j"$(( $(nproc) + 1 ))"
  )
}

for ANDROID_ABI_CMAKE in "${ANDROID_ABIS[@]}"; do
  echo "=============================================="
  echo " Building for ABI: ${ANDROID_ABI_CMAKE}"
  echo "=============================================="

  # --- Azure build matrix: per-ABI variables ---------------------------
  case "${ANDROID_ABI_CMAKE}" in
    armeabi-v7a)
      ARCH=arm; ANDROID_ARCH=armv7a; ANDROID_TARGET_ABI="eabi"; ANDROID_ABI_MESON=arm
      AUTOTOOLS_TARGET="${ARCH}-linux-android${ANDROID_TARGET_ABI}"
      ;;
    arm64-v8a)
      ARCH=aarch64; ANDROID_ARCH=aarch64; ANDROID_TARGET_ABI=""; ANDROID_ABI_MESON=aarch64
      AUTOTOOLS_TARGET="${ARCH}-none-linux-android"
      ;;
    x86)
      ARCH=i686; ANDROID_ARCH=i686; ANDROID_TARGET_ABI=""; ANDROID_ABI_MESON=x86
      AUTOTOOLS_TARGET="${ARCH}-pc-linux-android"
      ;;
    x86_64)
      ARCH=x86_64; ANDROID_ARCH=x86_64; ANDROID_TARGET_ABI=""; ANDROID_ABI_MESON=x86_64
      AUTOTOOLS_TARGET="${ARCH}-pc-linux-android"
      ;;
    *)
      echo "ERROR: unknown ABI ${ANDROID_ABI_CMAKE}" >&2; exit 1 ;;
  esac

  BUILD_ROOT="${WORK}/${ANDROID_ABI_CMAKE}"
  PREFIX="${BUILD_ROOT}/opt/android"
  LIBPATH0="${PREFIX}/lib"
  mkdir -p "${BUILD_ROOT}" "${PREFIX}"

  # --- 'Set environment variables' -------------------------------------
  # LOCAL VERIFICATION ONLY: the pipeline this recipe targets always runs on
  # Linux, so it hardcodes linux-x86_64; pick the host-matching prebuilt dir
  # instead so this also runs directly on a macOS host.
  NDK_HOST_TAG="linux-x86_64"
  [[ "$(uname -s)" == "Darwin" ]] && NDK_HOST_TAG="darwin-x86_64"
  NDK_TOOLCHAIN="${NDK}/toolchains/llvm/prebuilt/${NDK_HOST_TAG}"
  ANDROID_TARGET="${ARCH}-linux-android${ANDROID_TARGET_ABI}"
  ANDROID_TARGET_API="${ANDROID_ARCH}-linux-android${ANDROID_TARGET_ABI}${ANDROID_API}"
  export PATH="${PATH}:${PREFIX}/bin:${PREFIX}/lib:${PREFIX}/include:${NDK_TOOLCHAIN}/bin"

  LIBPATH1="${NDK_TOOLCHAIN}/sysroot/usr/lib"
  LIBPATH2="${NDK_TOOLCHAIN}/sysroot/usr/lib/${ARCH}-linux-android${ANDROID_TARGET_ABI}/${ANDROID_API}"
  LIBPATH3="${NDK_TOOLCHAIN}/sysroot/usr/lib/${ARCH}-linux-android${ANDROID_TARGET_ABI}"

  export LDFLAGS="-pie -Wl,-z,max-page-size=16384 -Wl,-rpath-link=${LIBPATH1} -L${LIBPATH1} -Wl,-rpath-link=${LIBPATH2} -L${LIBPATH2} -Wl,-rpath-link=${LIBPATH3} -L${LIBPATH3} -Wl,-rpath-link=${LIBPATH0} -L${LIBPATH0}"
  export AR=llvm-ar
  export AS="${ANDROID_TARGET_API}-clang"
  export CC="${ANDROID_TARGET_API}-clang"
  export CXX="${ANDROID_TARGET_API}-clang++"
  export LD=ld.lld
  export STRIP=llvm-strip
  export RANLIB=llvm-ranlib
  export CFLAGS="-fPIE -fPIC -I${PREFIX}/include --sysroot=${NDK_TOOLCHAIN}/sysroot -I${NDK_TOOLCHAIN}/sysroot/usr/include -Werror=implicit-function-declaration"
  export CXXFLAGS="${CFLAGS}"
  export CPPFLAGS="${CXXFLAGS}"
  export PKG_CONFIG_PATH="${LIBPATH0}/pkgconfig"
  export PKG_CONFIG_LIBDIR="${PKG_CONFIG_PATH}"

  ABI_SRC="${BUILD_ROOT}/src"
  mkdir -p "${ABI_SRC}"
  cd "${ABI_SRC}"
  for archive in "${SRC}"/*.tar.gz "${SRC}"/*.tar.xz "${SRC}"/*.tar.bz2; do
    [[ -e "${archive}" ]] || continue
    tar xf "${archive}"
  done

  # --- 'Compile libiconv' (autotools, static only) ----------------------
  ( cd "libiconv-${ICONV_VERSION}"
    ./configure --host="${AUTOTOOLS_TARGET}" --prefix="${PREFIX}" --libdir="${LIBPATH0}" \
      --disable-rpath --enable-static --disable-shared --with-pic \
      --disable-maintainer-mode --disable-silent-rules --disable-gtk-doc \
      --disable-introspection --disable-nls
    make -j"$(( $(nproc) + 1 ))"
    make install )

  # --- 'Compile libffi' (autotools, static only) ------------------------
  ( cd "libffi-${FFI_COMMIT}"
    NOCONFIGURE=true autoreconf -v -i
    ./configure --host="${AUTOTOOLS_TARGET}" --prefix="${PREFIX}" --libdir="${LIBPATH0}" \
      --enable-static --disable-shared --disable-multi-os-directory --disable-multilib
    # libffi's configure (via its AX_ENABLE_BUILDDIR macro) does the real
    # build inside a subdirectory named after --host, and leaves the
    # top-level Makefile as a multi-host dispatcher that only works when
    # invoked from a checkout shared by several concurrent host builds.
    # Our single-host build has no such sibling, so the dispatcher's
    # "all-configured" target fails; build in the real subdirectory instead.
    cd "${AUTOTOOLS_TARGET}"
    make -j"$(( $(nproc) + 1 ))"
    make install )

  # --- 'Compile gettext' (autotools, static only) -----------------------
  ( cd "gettext-${GETTEXT_VERSION}"
    ./configure --host="${AUTOTOOLS_TARGET}" --prefix="${PREFIX}" --libdir="${LIBPATH0}" \
      --disable-rpath --disable-libasprintf --disable-java --disable-native-java \
      --disable-openmp --disable-curses --enable-static --disable-shared --with-pic \
      --disable-maintainer-mode --disable-silent-rules --disable-gtk-doc \
      --disable-introspection
    make -j"$(( $(nproc) + 1 ))"
    make install )

  # --- 'Compile pcre-8.45' (cmake template) -----------------------------
  # CMake probes for strtoq() with the C compiler (finds it) but it's then
  # used from C++ context where it doesn't exist on Android; renaming it
  # out of CMakeLists.txt is upstream FluidSynth's own workaround.
  ( cd "pcre-${PCRE_VERSION}"
    perl -pi -e 's/strtoq/strtoqqqq/g' CMakeLists.txt )
  cmake_invoke "$(pwd)/pcre-${PCRE_VERSION}" "${ABI_SRC}/pcre-${PCRE_VERSION}/build" \
    -DPCRE_SUPPORT_UNICODE_PROPERTIES=1 -DPCRE_SUPPORT_UTF=1 \
    -DPCRE_BUILD_PCRECPP=0 -DPCRE_BUILD_TESTS=0
  make -C "${ABI_SRC}/pcre-${PCRE_VERSION}/build" install

  # --- 'Compile glib (meson)' -------------------------------------------
  GLIB_DIR="glib-${GLIB_VERSION}.${GLIB_EXTRAVERSION}"
  ( cd "${GLIB_DIR}"
    PKGCFG="$(command -v pkg-config)"
    cat > cross_file.ini <<EOF
[host_machine]
system = 'android'
cpu_family = '${ANDROID_ABI_MESON}'
cpu = '${ANDROID_ARCH}'
endian = 'little'

[binaries]
c = '${NDK_TOOLCHAIN}/bin/${CC}'
cpp = '${NDK_TOOLCHAIN}/bin/${CXX}'
ar = '${NDK_TOOLCHAIN}/bin/${AR}'
as = '${NDK_TOOLCHAIN}/bin/${AS}'
ld = '${NDK_TOOLCHAIN}/bin/${LD}'
strip = '${NDK_TOOLCHAIN}/bin/${STRIP}'
ranlib = '${NDK_TOOLCHAIN}/bin/${RANLIB}'
pkgconfig = '${PKGCFG}'

[properties]
prefix = '${PREFIX}'
c_args = '${CFLAGS}'
cpp_args = '${CXXFLAGS}'
pkg_config_libdir = '${PKG_CONFIG_LIBDIR}'
c_link_args = '${LDFLAGS}'

[project options]
libmount = 'disabled'
xattr = false
selinux = 'disabled'
nls = 'disabled'
glib_debug = 'disabled'
glib_assert = false
glib_checks = false
libelf = 'disabled'
EOF
    # env -i: CC/CXX being set in our environment would make meson treat
    # them as the *host* compiler rather than the cross compiler, which
    # breaks its sanity check (it would try to run ARM binaries on x86_64).
    # LOCAL VERIFICATION ONLY (macOS host, not the Docker/Ubuntu build this
    # recipe is meant to run on): gdbus-codegen (a host-side build tool GLib
    # generates and runs during its own build, not part of the cross-compiled
    # output) imports the stdlib `distutils`, removed in Python >= 3.12. On
    # macOS with a newer Homebrew Python as the default, put one that still
    # has it (3.11) first on PATH for this step only; on any other host this
    # is a no-op since that path doesn't exist.
    GLIB_HOST_PATH="${PATH}"
    if [[ "$(uname -s)" == "Darwin" && -d "/opt/homebrew/opt/python@3.11/bin" ]]; then
      GLIB_HOST_PATH="/opt/homebrew/opt/python@3.11/bin:${PATH}"
    fi
    env -i bash -c "export PATH='${GLIB_HOST_PATH}' && export PKG_CONFIG_LIBDIR='${PKG_CONFIG_LIBDIR}' && meson setup build --cross-file cross_file.ini --prefix='${PREFIX}'"
    # meson bakes the configuring python's absolute path directly into
    # build.ninja's codegen rules (as the literal command, not relying on
    # the generated scripts' own shebang), and meson itself isn't installed
    # for 3.11. Rewrite the baked-in interpreter path instead of chasing
    # meson's interpreter choice. Only applicable on the macOS path above.
    if [[ "$(uname -s)" == "Darwin" ]]; then
      perl -pi -e 's{/opt/homebrew/bin/python3(?!\.\d)}{/opt/homebrew/opt/python\@3.11/bin/python3.11}g' build/build.ninja
    fi
    PATH="${GLIB_HOST_PATH}" ninja -C build
    PATH="${GLIB_HOST_PATH}" ninja -C build install )

  # --- 'Compile libogg' (cmake template) --------------------------------
  cmake_invoke "$(pwd)/libogg-${OGG_VERSION}" "${ABI_SRC}/libogg-${OGG_VERSION}/build" -DINSTALL_DOCS=0
  make -C "${ABI_SRC}/libogg-${OGG_VERSION}/build" install

  # --- 'Compile libvorbis' (cmake template) -----------------------------
  cmake_invoke "$(pwd)/libvorbis-${VORBIS_VERSION}" "${ABI_SRC}/libvorbis-${VORBIS_VERSION}/build"
  make -C "${ABI_SRC}/libvorbis-${VORBIS_VERSION}/build" install

  # --- 'Compile flac' (cmake template) -----------------------------------
  cmake_invoke "$(pwd)/flac-${FLAC_VERSION}" "${ABI_SRC}/flac-${FLAC_VERSION}/build" \
    -DCMAKE_C_STANDARD=99 -DCMAKE_C_STANDARD_REQUIRED=1 -DWITH_ASM=0 \
    -DBUILD_CXXLIBS=0 -DBUILD_PROGRAMS=0 -DBUILD_EXAMPLES=0 -DBUILD_DOCS=0 \
    -DINSTALL_MANPAGES=0
  make -C "${ABI_SRC}/flac-${FLAC_VERSION}/build" install

  # --- 'Compile opus' (cmake template) -----------------------------------
  cmake_invoke "$(pwd)/opus-${OPUS_VERSION}" "${ABI_SRC}/opus-${OPUS_VERSION}/build" \
    -DBUILD_PROGRAMS=0 -DOPUS_MAY_HAVE_NEON=1 -DCMAKE_C_STANDARD=99 \
    -DCMAKE_C_STANDARD_REQUIRED=1
  make -C "${ABI_SRC}/opus-${OPUS_VERSION}/build" install

  # --- 'Compile libsndfile' (cmake template) -----------------------------
  # LOCAL VERIFICATION ONLY: libsndfile's CMakeChecks look for a
  # `PythonInterp` (host build tool, used to generate a header at configure
  # time) via the legacy FindPythonInterp module, which searches for an
  # executable literally named `python` — absent on a modern macOS/Homebrew
  # PATH that only has `python3`. Point it at python3 explicitly.
  cmake_invoke "$(pwd)/libsndfile-${SNDFILE_VERSION}" "${ABI_SRC}/libsndfile-${SNDFILE_VERSION}/build" \
    -DBUILD_PROGRAMS=0 -DBUILD_EXAMPLES=0 -DPYTHON_EXECUTABLE="$(command -v python3)"
  make -C "${ABI_SRC}/libsndfile-${SNDFILE_VERSION}/build" install

  # --- 'Compile oboe' (cmake template, custom install command) -----------
  OBOE_DIR="oboe-${OBOE_VERSION}"
  cmake_invoke "$(pwd)/${OBOE_DIR}" "${ABI_SRC}/${OBOE_DIR}/build"
  ( cd "${ABI_SRC}/${OBOE_DIR}/build"
    cp liboboe.* "${PREFIX}/lib/"
    # LOCAL VERIFICATION ONLY: BSD cp (macOS) has no -u; this only ever
    # copies once per ABI build anyway, so a plain recursive copy is equivalent.
    cp -R "${ABI_SRC}/${OBOE_DIR}/include/oboe" "${PREFIX}/include" )

  # --- 'Create fake oboe.pc' ----------------------------------------------
  # oboe ships no pkg-config file; FluidSynth's CMake looks for one.
  cat > "${PKG_CONFIG_PATH}/oboe-1.0.pc" <<EOF
prefix=${PREFIX}
exec_prefix=\${prefix}
libdir=\${prefix}/lib
includedir=\${prefix}/include

Name: Oboe
Description: Oboe library
Version: ${OBOE_VERSION}
Libs: -L\${libdir} -loboe -landroid -llog
Cflags: -I\${includedir}
EOF

  # --- 'Compile libinstpatch' (cmake template) ----------------------------
  cmake_invoke "$(pwd)/libinstpatch-${INSTPATCH_VERSION}" "${ABI_SRC}/libinstpatch-${INSTPATCH_VERSION}/build"
  make -C "${ABI_SRC}/libinstpatch-${INSTPATCH_VERSION}/build" install

  # --- 'Compile .' (fluidsynth itself, cmake template) --------------------
  FLUIDSYNTH_DIR="fluidsynth-${FLUIDSYNTH_VERSION}"
  cmake_invoke "$(pwd)/${FLUIDSYNTH_DIR}" "${ABI_SRC}/${FLUIDSYNTH_DIR}/build" \
    -Denable-opensles=1 -Denable-floats=1 -Denable-oboe=1 -Denable-dbus=0 \
    -Denable-oss=0 -Denable-openmp=0
  # --- 'Install fluidsynth' ------------------------------------------------
  make -C "${ABI_SRC}/${FLUIDSYNTH_DIR}/build" install

  # --- 'Collecting artifacts' ----------------------------------------------
  # Mirrors the Azure step: keep only unversioned, dynamically-linked .so
  # files, matching the shape FluidSynth's own fluidsynth-android24.zip
  # release ships and MANUL's own app build expects under
  # fluidsynth/lib/<ABI>/.
  DEST="${OUT}/${ANDROID_ABI_CMAKE}"
  mkdir -p "${DEST}"
  cp -a "${LIBPATH0}"/*.so "${DEST}/" 2>/dev/null || true
  # Drop versioned symlinks/files (libfoo.so.1, libfoo.so.1.2.3) — only the
  # unversioned SONAME-less filename is what MANUL's app build links against.
  find "${DEST}" -name '*.so.*' -delete

  echo "Artifacts for ${ANDROID_ABI_CMAKE} in ${DEST}:"
  ls -la "${DEST}"
done

echo ""
echo "Build complete. Rebuilt libraries are under: ${OUT}/<abi>/"
echo "Pass the directory for the one library you changed to relink/relink.sh"
echo "as --libs-dir; see INSTRUCTIONS.md."
