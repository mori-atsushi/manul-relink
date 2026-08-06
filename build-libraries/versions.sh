#!/usr/bin/env bash
# Pinned tool and dependency versions for the Android relink build.
#
# Sourced by fetch-toolchain.sh and build.sh so every script (and
# INSTRUCTIONS.md, which quotes the same numbers) agrees on exactly one
# version of each thing. Do not bump anything here without also updating
# INSTRUCTIONS.md.
#
# Where these numbers come from: FluidSynth's own Android CI recipe,
# .azure/azure-pipelines-android.yml at tag v2.4.7 in
# https://github.com/FluidSynth/fluidsynth — the same pipeline that produced
# the fluidsynth-2.4.7-android24.zip release artifact MANUL vendors. This
# script is a line-by-line translation of that pipeline's `variables:` block
# and dependency-download step for local/manual use, not an independent
# design.

set -euo pipefail

# --- Android toolchain -------------------------------------------------
#
# The Azure pipeline pins the NDK by a fixed path,
# /usr/local/lib/android/sdk/ndk/27.2.12479018, which is how GitHub/Azure's
# hosted Ubuntu 22.04 image exposes NDK side-by-side version 27.2.12479018.
# That side-by-side version number is Google's own name for what it
# publishes to end users as "r27c" (confirmed against Google's SDK
# repository manifest, repository2-3.xml, which lists
# `ndk;27.2.12479018` with download `android-ndk-r27c-linux.zip`). We
# download it directly instead of via sdkmanager so this recipe does not
# need a full Android SDK install.
NDK_VERSION="r27c"                     # = side-by-side 27.2.12479018
NDK_URL="https://dl.google.com/android/repository/android-ndk-${NDK_VERSION}-linux.zip"
# SHA-1 published by Google in repository2-3.xml for this exact archive
# (Google does not publish a SHA-256 for NDK archives).
NDK_SHA1="090e8083a715fdb1a3e402d0763c388abb03fb4e"

# CMake. The pipeline's "Use recent CMake Version" step (which would add
# Kitware's apt repo for a newer CMake) is disabled (`enabled: 'false'`), so
# the actual build in the pipeline uses whatever `apt-get install cmake`
# resolves to on the `ubuntu-22.04` hosted image, which is Ubuntu 22.04's
# packaged CMake, 3.22.1. We pin that exact release from Kitware's own
# GitHub releases instead of trusting a live apt mirror, so a rebuild years
# from now still gets the same compiler behavior.
CMAKE_VERSION="3.22.1"
CMAKE_URL="https://github.com/Kitware/CMake/releases/download/v${CMAKE_VERSION}/cmake-${CMAKE_VERSION}-linux-x86_64.tar.gz"
CMAKE_SHA256="73565c72355c6652e9db149249af36bcab44d9d478c5546fd926e69ad6b43640"

ANDROID_API="24"   # NOTE in the upstream pipeline: required for fseeko()/ftello() (libFLAC)
ANDROID_ABIS=("arm64-v8a" "armeabi-v7a" "x86" "x86_64")

# --- LGPL-covered project versions and source (must match, byte-for-byte,
# MANUL's internal provenance record for these binaries — these are copied
# from it, not independently chosen) ---------------------------------------
GLIB_VERSION="2.72"
GLIB_EXTRAVERSION="4"                  # glib-2.72.4
GLIB_SOURCE_URL="http://ftp.gnome.org/pub/gnome/sources/glib/2.72/glib-2.72.4.tar.xz"
GLIB_SOURCE_SHA256="8848aba518ba2f4217d144307a1d6cb9afcc92b54e5c13ac1f8c4d4608e96f0e"

SNDFILE_VERSION="1.2.2"
SNDFILE_SOURCE_URL="https://github.com/libsndfile/libsndfile/releases/download/1.2.2/libsndfile-1.2.2.tar.xz"
SNDFILE_SOURCE_SHA256="3799ca9924d3125038880367bf1468e53a1b7e3686a934f098b7e1d286cdb80e"

INSTPATCH_VERSION="1.1.6"
INSTPATCH_SOURCE_URL="https://github.com/swami/libinstpatch/archive/refs/tags/v1.1.6.tar.gz"
INSTPATCH_SOURCE_SHA256="8e9861b04ede275d712242664dab6ffa9166c7940fea3b017638681d25e10299"

FLUIDSYNTH_VERSION="2.4.7"
FLUIDSYNTH_SOURCE_URL="https://github.com/FluidSynth/fluidsynth/archive/refs/tags/v2.4.7.tar.gz"
FLUIDSYNTH_SOURCE_SHA256="7fb0e328c66a24161049e2b9e27c3b6e51a6904b31b1a647f73cc1f322523e88"

# --- Build-time-only dependencies ---------------------------------------
# None of these ship as .so files in the app (verify against the 17-file
# list this recipe produces): they are statically linked into GLib
# and FluidSynth's own build tooling, or are non-LGPL runtime libraries
# MANUL already publishes provenance for. Pinned to the exact versions the
# Azure pipeline downloads.
# Checksums below were computed by us (the manul-relink maintainers) by
# downloading each archive and running sha256sum, since upstream does not
# publish one; re-verify against a fresh download if in doubt.
ICONV_VERSION="1.17"
ICONV_URL="http://ftp.gnu.org/pub/gnu/libiconv/libiconv-${ICONV_VERSION}.tar.gz"
ICONV_SHA256="8f74213b56238c85a50a5329f77e06198771e70dd9a739779f4c02f65d971313"

GETTEXT_VERSION="0.22.5"
GETTEXT_URL="http://ftp.gnu.org/pub/gnu/gettext/gettext-${GETTEXT_VERSION}.tar.gz"
GETTEXT_SHA256="ec1705b1e969b83a9f073144ec806151db88127f5e40fe5a94cb6c8fa48996a0"

# The pipeline pins libffi to a commit, not a release (comment in the
# pipeline: "libffi 3.4.4 fails due to https://github.com/libffi/libffi/issues/760").
FFI_COMMIT="ce077e5565366171aa1b4438749b0922fce887a4"
FFI_URL="https://github.com/libffi/libffi/archive/${FFI_COMMIT}.tar.gz"
FFI_SHA256="8defc29b7fbe733976b1263ab281761c5ec71226a8e81c4822a030d299f875c8"

# Non-LGPL runtime libraries MANUL's internal provenance record already
# tracks (but doesn't require relinking). Rebuilding them is required to
# reproduce FluidSynth's Android build even though their source is not a
# relink obligation. URLs and checksums are the ones already recorded there.
OGG_VERSION="1.3.5"
OGG_URL="https://github.com/xiph/ogg/releases/download/v${OGG_VERSION}/libogg-${OGG_VERSION}.tar.gz"
OGG_SHA256="0eb4b4b9420a0f51db142ba3f9c64b333f826532dc0f48c6410ae51f4799b664"

VORBIS_VERSION="1.3.7"
VORBIS_URL="https://github.com/xiph/vorbis/releases/download/v${VORBIS_VERSION}/libvorbis-${VORBIS_VERSION}.tar.gz"
VORBIS_SHA256="0e982409a9c3fc82ee06e08205b1355e5c6aa4c36bca58146ef399621b0ce5ab"

FLAC_VERSION="1.4.3"
FLAC_URL="https://github.com/xiph/flac/archive/refs/tags/${FLAC_VERSION}.tar.gz"
FLAC_SHA256="0a4bb82a30609b606650d538a804a7b40205366ce8fc98871b0ecf3fbb0611ee"

OPUS_VERSION="1.5.2"
OPUS_URL="https://github.com/xiph/opus/archive/refs/tags/v${OPUS_VERSION}.tar.gz"
# The checksum originally recorded here (38f5cdda...) does not match this
# archive as actually downloaded from GitHub (verified by two independent
# fetches on 2026-08-06, both producing 9480e329...); it was simply wrong,
# not a corrupted/intercepted download. Re-verify against a fresh download
# if in doubt.
OPUS_SHA256="9480e329e989f70d69886ded470c7f8cfe6c0667cc4196d4837ac9e668fb7404"

PCRE_VERSION="8.45"
PCRE_URL="https://sourceforge.net/projects/pcre/files/pcre/${PCRE_VERSION}/pcre-${PCRE_VERSION}.tar.bz2/download"
PCRE_SHA256="4dae6fdcd2bb0bb6c37b5f97c33c2be954da743985369cddac3546e3218bffb8"

OBOE_VERSION="1.9.0"
OBOE_URL="https://github.com/google/oboe/archive/${OBOE_VERSION}.tar.gz"
OBOE_SHA256="e030276d25b8bdfaeb04f66646821b1ba4a2b6a580a7e84fb144a478eaecd663"
