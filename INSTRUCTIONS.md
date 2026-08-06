# Relinking walkthrough

This rebuilds one of MANUL's four bundled LGPL-2.1-or-later libraries
(FluidSynth, libsndfile, libinstpatch, GLib) with your own changes, and
produces an installable app that runs your rebuilt copy in place of the one
MANUL shipped.

**No step below requires contacting MANUL, creating an account with MANUL, or
agreeing to any terms beyond what already governs your use of the app.**
Everything you need is either in this repository or linked from it below.

## What you'll need

| Tool | Version | Where to get it |
|---|---|---|
| A Linux (or Docker-capable) machine, x86_64 | — | — |
| Android NDK | r27c (side-by-side `27.2.12479018`) | `https://dl.google.com/android/repository/android-ndk-r27c-linux.zip` |
| CMake | 3.22.1 | `https://github.com/Kitware/CMake/releases/download/v3.22.1/cmake-3.22.1-linux-x86_64.tar.gz` |
| Docker (optional but recommended) | any recent version | `https://docs.docker.com/engine/install/` |
| A Java runtime (JRE 11+) | any recent JRE/JDK | e.g. `https://adoptium.net/`, or your distro's `openjdk-17-jre` package |
| bundletool | 1.18.3 | `https://github.com/google/bundletool/releases/download/1.18.3/bundletool-all-1.18.3.jar` |
| Android platform tools (`adb`) | any recent version | `https://developer.android.com/tools/releases/platform-tools` |

`build-libraries/fetch-toolchain.sh` downloads and checksum-verifies the NDK
and CMake for you — you don't have to fetch those two by hand, they're listed
here so you know exactly what will land on your machine and can verify it
yourself if you'd rather not run the script. The exact versions above are the
versions FluidSynth's own Android CI recipe uses to build the release
artifact MANUL vendors (see
[`build-libraries/versions.sh`](build-libraries/versions.sh) for the
reasoning behind each pin, and the original recipe it was copied from:
[`.azure/azure-pipelines-android.yml`](https://github.com/FluidSynth/fluidsynth/blob/v2.4.7/.azure/azure-pipelines-android.yml)
at FluidSynth's `v2.4.7` tag).

## 1. Get this release's materials

From this repository's release page, find the tag matching the version shown
in MANUL's Settings screen (`android-vX.Y.Z`). Download its release assets:
the app bundle (`.aab`), the four libraries' source archives at the exact
version bundled (plus any patches MANUL applied), and `SHA256SUMS`. Check
each downloaded file against `SHA256SUMS` and the app bundle's checksum
against the value in that release's `RELEASE.md` before going further — a
mismatch means you have the wrong file, not that anything here is wrong.

Check out the tag itself to get:

- `build-libraries/` — this build recipe.
- `relink/relink.sh` — the repackaging script.
- `LIBRARIES.md` — per-library version/license/upstream detail for that
  release.

## 2. Make your changes

If you're not changing anything and just want to confirm the process works,
skip straight to building as-is — `build-libraries/build.sh` downloads
pristine sources on its own and there's nothing to do here.

To change one of the four libraries:

1. Extract its source archive (downloaded in step 1) into a working directory.
2. Make your changes.
3. Re-archive it (same format: `tar czf` / `tar cJf`) under the **exact**
   filename `build-libraries/build.sh` downloads it as — the second argument
   to that library's `fetch` call in `build-libraries/build.sh` (e.g.
   `fluidsynth-2.4.7.tar.gz`; this is not the same as the release asset's
   filename).
4. Place it at `build-libraries/work/src/<that filename>` **before** running
   `build.sh`.

`fetch()` skips downloading (and re-checking against the pinned upstream
checksum) any file already present at that path, so your modified archive is
used as-is — the pinned checksum only guards against a corrupted or tampered
*download*, not against your own intentional change.

## 3. Rebuild

```sh
cd build-libraries
docker build -t manul-relink-build .
mkdir -p work out
docker run --rm -v "$(pwd)/work:/work/work" -v "$(pwd)/out:/work/out" manul-relink-build
```

The `work` mount is what makes step 2's modified archive (placed at
`build-libraries/work/src/<filename>` on the host) visible inside the
container — without it, `build.sh` would only ever see the pristine sources
it downloads itself.

This cross-compiles all four ABIs MANUL ships (`arm64-v8a`, `armeabi-v7a`,
`x86`, `x86_64`) at Android API level 24, producing
`out/<abi>/lib<name>.so` for every library the recipe builds — not just the
one you changed. You only need the ones for the library you actually
modified; see `build-libraries/build.sh` for what it produces where.

Without Docker: run `./fetch-toolchain.sh` then `./build.sh` directly on an
Ubuntu 22.04 x86_64 host with the apt packages listed in `Dockerfile`
installed. The Dockerfile exists so you don't have to match that host
environment by hand.

Building all four ABIs takes a while — GLib and FluidSynth are the slowest
parts. This is inherent to the recipe: it's a faithful reproduction of the
same build FluidSynth's own CI runs to produce the release artifact MANUL
vendors, and that recipe cross-compiles nine other libraries first.

## 4. Get a signing keystore

Any Android keystore works, including one you already have. If you don't
have one, `keytool` (part of any JDK) creates a throwaway one:

```sh
keytool -genkeypair -v \
  -keystore my-relink.jks -alias my-relink \
  -keyalg RSA -keysize 2048 -validity 10000 \
  -storepass changeit -keypass changeit
```

This key is **yours** — it is not MANUL's release key. Because the relinked
app keeps MANUL's package name but is signed with a different key, Android
will not treat it as an update to any Play Store copy you have installed;
see step 6 for how to install it in that case.

## 5. Repackage and sign

```sh
cd relink
./relink.sh \
  --aab /path/to/downloaded-release.aab \
  --library fluidsynth \
  --libs-dir ../build-libraries/out \
  --keystore /path/to/my-relink.jks \
  --ks-pass changeit \
  --key-alias my-relink \
  --key-pass changeit \
  --bundletool /path/to/bundletool-all-1.18.3.jar \
  --output ./relinked-universal.apk
```

- `--library` is one of `fluidsynth`, `libsndfile`, `libinstpatch`, `glib` —
  whichever project you changed. It's used to sanity-check the filenames you
  provide, not to pick which files get replaced; the script fails loudly if
  they don't match, rather than silently doing nothing.
- `--libs-dir` points at a directory with one subdirectory per ABI
  (`arm64-v8a/`, `armeabi-v7a/`, `x86/`, `x86_64/`), each holding that ABI's
  rebuilt `.so`. `build-libraries/out` from the previous step is already in
  this shape. You can also pass a single file with `--lib <file> --abi
  <abi>` instead, if you only rebuilt one ABI.
- The script only unpacks the bundle, swaps the named `.so` files, repacks
  it, and calls `bundletool build-apks --mode=universal` with your keystore.
  No Android compilation happens here — that already happened in step 3.

`relink.sh --help` prints the full option list. It fails with a specific
error message (missing tool, unknown ABI, filename that doesn't belong to the
library you named, bundletool failure) rather than continuing on bad input.

## 6. Install

The relinked app keeps MANUL's package name (`com.manulscore`), only the
signing key changes. Android identifies installed apps by package name, not
signing key, and refuses to install a package over an existing install
signed with a different key — so if you have MANUL installed from the Play
Store, **uninstall it first** (this removes its local data):

```sh
adb uninstall com.manulscore
adb install ./relink/relinked-universal.apk
```

If you don't already have MANUL installed, `adb install` works directly.
Either way, this installs as a build signed with your own key, not MANUL's
release key — it cannot receive updates from the Play Store, and a later
Play Store install would in turn refuse to install over this one for the
same reason, until you uninstall again.

## If something goes wrong

- **Checksum mismatch on the AAB**: you downloaded the wrong file, or a
  transfer got corrupted. Re-download from the release page.
- **`relink.sh` says a filename doesn't belong to the library you named**:
  double check `--library`, or that your rebuild actually produced the
  expected output filename (see `build-libraries/build.sh`'s "Collecting
  artifacts" step for what it expects).
- **Docker build fails downloading the NDK or CMake**: `fetch-toolchain.sh`
  verifies checksums before extracting; a checksum failure means the
  download was corrupted or intercepted, not that the pinned version is
  wrong — retry the download.
- **Build succeeds but the app crashes**: this walkthrough covers building
  and installing, not debugging your own changes to the libraries. MANUL
  provides no support for a relinked build; see `README.md`.
