# manul-relink

This repository exists to satisfy an **LGPL-2.1 obligation**, not to offer a
supported extension point for MANUL.

MANUL ([`com.manulscore`](https://play.google.com/store/apps/details?id=com.manulscore))
bundles four LGPL-2.1-or-later libraries — FluidSynth, libsndfile, libinstpatch
and GLib — as prebuilt native (`.so`) files it does not build itself. The
LGPL's exception for a library already present on the user's system does not
apply on Android, which ships none of these, so MANUL takes the license's other
route: publishing everything a recipient needs to rebuild any of the four
libraries, with their own modifications, and produce a working app around the
result.

**This is not:**

- A place to file feature requests or bug reports about MANUL. Use MANUL's own
  issue tracker for that.
- A supported way to extend or modify MANUL. What is published here covers
  replacing the four LGPL libraries and nothing else. MANUL's own application
  code is not documented here, is not kept stable between releases, and is not
  supported.
- A place where MANUL provides help building or installing a relinked copy.
  Feedback and crash reporting channels cover the officially released app only.

## What is here

Each release of MANUL that bundles an LGPL-covered library gets one tag here,
named to match the app version shown in its Settings screen (`android-vX.Y.Z`),
with a matching GitHub Release:

- **In the tag's tree**: a build recipe (`build-libraries/`) that reproduces
  the cross-compile for all four supported Android ABIs, a relink script
  (`relink/relink.sh`) that swaps a rebuilt library into a copy of the
  released app package, step-by-step instructions (`INSTRUCTIONS.md`), and
  `LIBRARIES.md` describing that release's libraries.
- **Attached to the Release as assets**: the source of the four LGPL
  libraries at the exact versions bundled, a `SHA256SUMS` for those archives,
  and the exact app package distributed for that release with its own
  checksum recorded in `RELEASE.md`.

`RELEASE.md` is a running log — every release appends a section, so the
current tag's copy also lists every release before it.

See [`INSTRUCTIONS.md`](INSTRUCTIONS.md) for the actual walkthrough.

## Retention

**No tag, and nothing attached to a tag, is ever removed from this repository**
once published — including when a newer release makes it obsolete. Every
release stays reachable by the people who were running it. If a future release
of MANUL drops all LGPL-covered libraries, this repository simply stops
gaining new tags; nothing already published is touched.
