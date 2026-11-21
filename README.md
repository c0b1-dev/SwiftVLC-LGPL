<picture>
  <source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/harflabs/SwiftVLC/main/Assets/logo-dark.svg">
  <source media="(prefers-color-scheme: light)" srcset="https://raw.githubusercontent.com/harflabs/SwiftVLC/main/Assets/logo-light.svg">
  <img alt="SwiftVLC" src="https://raw.githubusercontent.com/harflabs/SwiftVLC/main/Assets/logo-light.svg" width="260">
</picture>

[![Tests](https://github.com/harflabs/SwiftVLC/actions/workflows/test.yml/badge.svg)](https://github.com/harflabs/SwiftVLC/actions/workflows/test.yml)
[![codecov](https://codecov.io/gh/harflabs/SwiftVLC/branch/main/graph/badge.svg)](https://codecov.io/gh/harflabs/SwiftVLC)
[![Swift versions](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fharflabs%2FSwiftVLC%2Fbadge%3Ftype%3Dswift-versions)](https://swiftpackageindex.com/harflabs/SwiftVLC)
[![Platforms](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fharflabs%2FSwiftVLC%2Fbadge%3Ftype%3Dplatforms)](https://swiftpackageindex.com/harflabs/SwiftVLC)

A Swift wrapper around [libVLC](https://www.videolan.org/vlc/libvlc.html) for iOS, macOS, tvOS, visionOS, and Mac Catalyst.

---

> ### This is a fork — read before building
>
> `c0b1-dev/SwiftVLC-LGPL`, branch `cobiplayer-lgpl`. Two differences from upstream
> [harflabs/SwiftVLC](https://github.com/harflabs/SwiftVLC) matter:
>
> 1. **GPL-free libVLC.** VLC's licence switch reaches only the contribs; VLC's own GPL code is
>    compiled whatever it says. Left out here: the teletext library `zvbi`, VLC's GPL-2+ modules
>    (`VLC_GPL_MODULES` in `scripts/build-libvlc.sh`) and FFmpeg's yadif inside the deinterlace
>    plugin (patch 0008), each with a build guard that hard-fails if it reappears. Upstream's
>    prebuilt binary contains them — linking that binary rules out App Store distribution, and
>    nothing in the build warns you.
> 2. **Seven libVLC patches** (`scripts/patches/`, 0001 and 0003–0008; there is no 0002). The
>    important one is **0004, "adopted layer"**: libVLC's native vout adopts an
>    `AVSampleBufferDisplayLayer` owned by the host app. That is what makes VideoToolbox
>    hardware decoding *and* Picture-in-Picture work at the same time — with the stock setup
>    you get one or the other. **0006** backports an upstream MP4 seek fix that the pinned
>    revision predates, **0007** lets the app set a proxy for libVLC's http modules, **0008**
>    takes the GPL yadif out (see below).
>
> Fetch the prebuilt engine with `./scripts/setup-dev.sh`, which pulls from **this fork's**
> releases. Building it yourself takes about 20 minutes: `./scripts/build-libvlc.sh`.
> `Vendor/libvlc.xcframework` (4.4 GB) is deliberately not in git.
>
> ⚠ A release asset is only as current as the patches it was built from. `libvlc-20261121`,
> tagged at the merge that brings this text, contains `0001` and `0003`–`0008` and none of
> VLC's GPL modules: the 2026-11-21 build, its third-party libraries reused unchanged from the
> previous release (see the Xcode-update and automake notes below). `libvlc-20261111` contains
> `0001` and `0003`–`0007`, `libvlc-20260925` `0001`–`0006`. After changing a patch, rebuild
> **and cut a new release** — otherwise
> `setup-dev.sh` and Cobi Player's Xcode Cloud build (which pins the asset's checksum in
> `ci_scripts/engine.env`) keep using the old binary, with a green build and no warning.
>
> ⚠ `libvlc-20261111` and every release before it still link VLC's GPL-2+ modules (`syslog`,
> `file_logger`, `rotate`, `sap`, `stream_out_rtp`, `stream_out_cycle`, control `dummy`) and
> FFmpeg's GPL yadif (found 2026-11-21). Don't build an app on them.

---

## Why?

AVFoundation is excellent for Apple's native media stack, but its
container, codec, subtitle, and network-protocol support is limited to
what Apple ships. Apps that need MKV, SSA/ASS subtitles, RTSP, SMB,
UPnP, or other VLC-backed formats and protocols need a broader engine.

[VLC](https://www.videolan.org/)'s engine, **libVLC**, supports a broad set of codecs, containers, subtitles, and network protocols through embeddable C APIs.

VideoLAN's Apple wrapper, [VLCKit](https://code.videolan.org/videolan/VLCKit), is written primarily in Objective-C. It uses delegates, KVO, `NSNotificationCenter`, and manual thread management, which is a faithful reflection of the era it was designed in.

**SwiftVLC** wraps libVLC 4.0 directly in Swift, with no Objective-C layer in between. It is built for `@Observable`, `async/await`, and `VideoView(player)`.

## SwiftVLC vs VLCKit

| | SwiftVLC | VLCKit |
|---|---|---|
| **Language** | Swift 6 | Objective-C |
| **Bindings** | Direct C → Swift | C → Objective-C → Swift bridging |
| **State management** | `@Observable`, drives SwiftUI directly | KVO, `NSNotificationCenter`, and delegates |
| **Concurrency** | `@MainActor`, `Sendable`, `async/await` | Manual thread dispatch, no isolation |
| **Video rendering** | `VideoView(player)` | App-supplied view setup plus drawable configuration |
| **Errors** | `throws(VLCError)`, typed and exhaustive | `NSError` codes |
| **Events** | `AsyncStream<PlayerEvent>` with multiple consumers | `NSNotificationCenter` |
| **libVLC generation** | 4.0 | 3.x stable line; 4.0 alpha packages exist |
| **SwiftUI PiP** | iOS via libVLC's native AVKit-backed drawable path; macOS private backend is SPI opt-in | App-supplied integration |
| **Swift 6 safe** | Yes, with strict concurrency | No |

## Features

- `@Observable` player: state, current time, duration, tracks, and volume drive SwiftUI directly.
- `VideoView(player)` handles the rendering lifecycle in a single SwiftUI view.
- Typed errors via `throws(VLCError)` instead of error codes.
- Asynchronous media parsing: `try await media.parse()` with cancellation support.
- 10-band equalizer with libVLC's built-in presets.
- A-B looping, playback rate control, and subtitle and audio delay.
- Picture-in-Picture on iOS with full playback controls; macOS native PiP is available only through an explicit private-API SPI opt-in.
- Media discovery and renderer discovery through services exposed by the bundled libVLC plugins.
- 360° video with full viewpoint control over yaw, pitch, roll, and field of view.
- Asynchronous thumbnail generation at arbitrary timestamps.
- `MediaListPlayer` for playlist playback with loop and repeat modes.

## Requirements

- Swift 6.3+ / Xcode 26+
- iOS 18+ / macOS 15+ / tvOS 18+ / visionOS 2+ / Mac Catalyst 18+

## Installation

In Xcode, choose **File → Add Package Dependencies**, paste the repo
URL, and Xcode will pick up the latest release automatically:

```
https://github.com/harflabs/SwiftVLC.git
```

From a `Package.swift` manifest, add a dependency and pin to the
current release. The version string lives on the
[releases page](https://github.com/harflabs/SwiftVLC/releases).

```swift
.package(url: "https://github.com/harflabs/SwiftVLC.git", from: "x.y.z")
```

The pre-built libVLC xcframework downloads automatically via SPM. It's a large binary (multi-GB unstripped; the release zip is a few hundred MB).

## Quick Start

```swift
import SwiftUI
import SwiftVLC

struct PlayerView: View {
  @State private var player = Player()

  var body: some View {
    VideoView(player)
      .onAppear {
        try? player.play(url: URL(string: "https://example.com/video.mp4")!)
      }
  }
}
```

`Player.play(url:)` expects a direct media stream or file URL. It does
not auto-resolve `.pls` or classic `.m3u` playlist containers; use
`MediaListPlayer` or fetch and parse the playlist to its inner stream
URL before passing it to `Player`. HLS `.m3u8` URLs are supported here
because they are streaming manifests rather than playlists of separate
media URLs.

### Common Operations

```swift
// Playback
let player = Player()
try player.play(url: videoURL)
player.pause()
player.stop()
try player.seek(to: PlaybackPosition(0.5)) // Seek to 50%
try player.setPlaybackRate(1.5)            // 1.5x speed
try player.setAudioVolume(0.8)             // 80% volume
player.isMuted = true

// Tracks
player.selectedSubtitleTrack = player.subtitleTracks[1]

// Metadata
let media = try Media(url: videoURL)
let metadata = try await media.parse()
print(metadata.title, metadata.duration)

// Events
for await event in player.events {
  switch event {
  case .stateChanged(let state): ...
  case .timeChanged(let time): ...
  default: break
  }
}
```

## Documentation

Full API reference is hosted on Swift Package Index:
**[swiftpackageindex.com/harflabs/swiftvlc/documentation](https://swiftpackageindex.com/harflabs/swiftvlc/documentation)**

## Showcase Apps

The `Showcase/` directory contains separate folders, targets, and schemes for each showcase lane:

- **iOS.** Full-featured app target, also enabled for Mac Catalyst.
- **macOS.** Native macOS app target with the same showcase coverage, adapted into sidebar-driven Mac UI.
- **tvOS.** Native tvOS showcase app target with TV-focused focus navigation and Siri Remote controls.
- **visionOS.** Native visionOS app target with a focused simple playback showcase.

Showcase UI tests live under `Showcase/UITests/`. `iOSUITests` covers
the broad showcase flows, `macOSUITests` covers native macOS PiP, and
`tvOSUITests` is a placeholder target. The visionOS showcase does not
have a UI-test target.

## Testing

The core package uses a comprehensive
[Swift Testing](https://developer.apple.com/xcode/swift-testing/) suite
against the real libVLC binary, so regressions in the C bridge surface
immediately rather than hiding behind a fake. Showcase UI tests use
XCTest separately. CI runs package tests, lint, doc coverage, and
Showcase builds on pull requests and on `main`.

```bash
swift test
```

See [ARCHITECTURE.md](ARCHITECTURE.md#testing-strategy) for test tags,
fixtures, and structure.

## Development Setup

```bash
git clone https://github.com/harflabs/SwiftVLC.git
cd SwiftVLC
./scripts/setup-dev.sh
swift test
```

`main` tracks the latest released `url + checksum` form of the libVLC binary target. `setup-dev.sh` downloads `libvlc.xcframework.zip` into `Vendor/` and idempotently flips `Package.swift` plus the Showcase package reference to repo-local sources so package development and Showcase builds use the checkout on disk.

| `setup-dev.sh` flag | Effect |
|---|---|
| *(none)* | Download the latest release if `Vendor/` is empty; otherwise keep existing. |
| `vX.Y.Z` *(positional)* | Pin to a specific release tag. |
| `--force` | Re-download even if `Vendor/` already exists. |
| `--skip-download` | Only flip local references (`Package.swift` and the Showcase app). Expects `Vendor/` to already exist, which is useful after running `build-libvlc.sh`. |

## Building libVLC from Source

Needed only when bumping `VLC_HASH`, modifying build patches, or preparing a release. Day-to-day Swift development doesn't require it.

```bash
brew install autoconf automake libtool cmake pkg-config gettext
./scripts/build-libvlc.sh --all
```

Expect a full `--all` build to take tens of minutes on Apple Silicon. The script clones VLC at a pinned commit into `scripts/.build-libvlc/`, applies the source patches below, builds every contrib (FFmpeg, dav1d, x264, libass, …) per slice, and assembles the result into `Vendor/libvlc.xcframework`.

### Platform selection

| Flag | Platforms |
|---|---|
| *(default)* | iOS device + simulator |
| `--all` | iOS, tvOS, visionOS, macOS, Mac Catalyst (eight slices) |
| `--ios-only` / `--tvos-only` / `--visionos-only` / `--macos-only` / `--catalyst-only` | Replaces `Vendor/` with that single platform |
| `--tvos` / `--visionos` / `--macos` / `--catalyst` | Adds a platform to the default set |
| `--clean` / `--clean-build` | Wipe `scripts/.build-libvlc/` (the latter rebuilds afterwards) |
| `--hash=<sha>` | Override the pinned VLC commit |

> `*-only` flags **replace** the xcframework; any slices already in `Vendor/` are lost.

> ⚠ **After an Xcode update** VLC looks for the built contribs under a folder named after the new
> SDK (`contrib/arm64-iphoneos27.2`), while the contrib build's stamps say everything is done and
> install nothing there: configure stops with "Third party libraries not found!". Either point
> the new name at the old folder (`ln -s arm64-iphoneos26.5 arm64-iphoneos27.2`, likewise for
> the simulator and tvOS folders; Catalyst folders are named after the deployment target and are
> unaffected), which keeps the contribs byte-identical to the last release, or wipe
> `contrib/contrib-*` to rebuild them all (hours). The 2026-11-10 and 11-11 builds took the first way.

> ⚠ **After Homebrew updates automake**, a patch that changes a `Makefile.am` (0008 does) stops
> the build in the reused VLC tree: make regenerates `Makefile.in` with the automake that
> bootstrapped the tree, "automake-1.18: command not found". Run `./bootstrap` in
> `scripts/.build-libvlc/vlc` first; it regenerates the build files with the installed tools (and
> VLC's own libtool from `extras/tools`), and each slice then reconfigures itself. The contribs are
> not touched. The 2026-11-21 build did this (automake 1.18.1 → 1.19).

### Source patches

VLC master requires a few local patches for SwiftVLC's supported Apple toolchains. The script applies them in-tree on every invocation, idempotently:

1. **Mac Catalyst.** Teaches VLC's build system the `macabi` target triple and guards OpenGLES-only code paths.
2. **visionOS deployment target.** Adds the `xros` target triple so object files are stamped with visionOS 2.0 instead of the installed SDK version.
3. **Xcode 26 LDFLAGS.** Adds `-isysroot` to linker invocations so libSystem resolves.
4. **libtool 2.5 OBJC tag.** Adds `_LIBTOOLFLAGS = --tag=CC` to the `Makefile.am` files that contain `.m` sources. Older libtool versions inferred the tag; 2.5 refuses.
5. **Rust contribs disabled.** VLC's contribs pin `cargo-c 0.9.29`, which pulls `time 0.3.31` and fails type inference under the supported Rust toolchain. The only Rust contrib on Apple is `rav1e` (AV1 *encoder*); `dav1d` handles decoding.
6. **`dup3` / `pipe2`.** Forced unavailable via autoconf cache vars. iOS Simulator SDK 26 exports these Linux-only syscalls from libSystem, fooling configure into using them.

#### Backports

`scripts/patches/0006-mp4-roll-group-seek.patch` is upstream VLC commit `ae06c7155afa`
("demux: mp4: do not set sync_sample to sample_group_entry sample", 2026-02-11), which lands
after the pinned revision. Without it, seeking in an `.mp4` whose audio track carries a `roll`
sample group — which is what ffmpeg writes for AAC — sends the audio track back to sample 0 on
every seek, and the demuxer then reads forward one chunk per HTTP request until it catches up
with the video position. On a 2 GB file over the network that never finishes. Drop the patch
when `VLC_HASH` moves past that commit.

#### Own patches

`scripts/patches/0007-darwin-app-proxy.patch` (not upstream): iOS, tvOS and Mac Catalyst have no
system proxy setting `vlc_getProxyUrl()` could read, so an app that routes its own traffic (Cobi
Player's per-profile VPN connection) sets one with `vlc_darwin_SetProxyUrl()`, wrapped in Swift as
`NetworkProxy.set(_:)`. While it is set, libVLC never connects past it:

- `http://` goes to it in absolute form and `https://` as `CONNECT host:port`, by name; so do
  HLS/DASH segments and the legacy HTTP-based schemes libVLC switches to by itself (`icyx` for
  ICY radio answers, `unsv`, `itpc`, `mmsh` for "Pragma: features").
- Every other network scheme is refused in one place (`access_New` in `src/input/access.c`),
  the first URL as much as one a redirect leads to (`rtsp`, `ftp`, `smb`, …); local schemes such
  as `file` still work. FFmpeg gets an empty `protocol_whitelist`, so its own HLS demuxer can't
  fetch segments past the proxy (measured: without it, it does).
- A login in the URL (`http://user:pass@127.0.0.1:port`, percent-encoded) goes to the proxy as
  Basic `Proxy-Authorization` on every request and nowhere else: a keep-alive connection opened
  another way is dropped, not reused. The debug log shows only request lines. Cobi Player gives
  its local gateway a fresh login on every start, so no other process on the device can use it.
- A URL of another form becomes a closed port (`http://127.0.0.1:1`), never "no proxy".

The patch header lists every file it touches and why.

`scripts/patches/0008-deinterlace-without-yadif.patch` (not upstream): VLC's deinterlace plugin is
LGPL, but its yadif and yadif2x modes compile FFmpeg's yadif line filter (`deinterlace/yadif.h`,
GPL-2.0-or-later). The patch deletes those files and the two mode names from the plugin and from
the core's lists, so asking for `"yadif"` fails instead of opening a filter without it. The
default (`auto`, which picks `x`) does not change. `verify_no_gpl_objects` refuses an
xcframework with yadif's functions in it.

**VLC's GPL modules** are left out without a patch: `build-libvlc.sh` adds `VLC_GPL_MODULES` to
the removal list of VLC's own `extras/package/apple/build.sh`, which deletes their plugins before
it writes the static module list, and checks each slice's `static-libs-list` afterwards. Cobi
Player's `Scripts/check-engine-gpl-free.sh` refuses an engine with any of them, by their
descriptions.

⚠ The numbers `0007` and `0008` are this fork's own sequence. Upstream harflabs/SwiftVLC numbers its patches
independently and has an unrelated `0007-rapid-set-media-ownership.patch` (and 0002–0064 by now).
The file names differ, so nothing collides on disk, but "patch 0007" means different things in
the two repositories; when merging upstream's patch set, renumber ours rather than theirs.

`git reset --hard` only runs when HEAD is not at `VLC_HASH`, so the patches and per-platform build dirs survive repeated runs.

## Releasing

### This fork: `libvlc-YYYYMMDD`

The fork does **not** use `release.sh` (below): that is upstream's flow — `vX.Y.Z` tags on `main`,
all eight slices, `Package.swift` switched to a remote URL. Cobi Player needs five slices (iOS,
iOS Simulator, tvOS, tvOS Simulator, Mac Catalyst) and links `Vendor/` as a local package; Xcode
Cloud fetches the zip by the name and checksum pinned in Cobi Player's `ci_scripts/engine.env`.
A fork release is a GitHub Release named and tagged `libvlc-YYYYMMDD` (the build date) at the
`cobiplayer-lgpl` commit it was built from, with two assets (the zip must hold the
`libvlc.xcframework` folder itself: `setup-dev.sh` and `ci_post_clone.sh` unpack it into `Vendor/`):

```bash
./scripts/build-libvlc.sh --tvos --catalyst   # five slices into Vendor/libvlc.xcframework
./scripts/check-libvlc-manifest.sh            # members per slice unchanged (or --write + review)
cd Vendor && ditto -c -k --norsrc --noextattr --keepParent libvlc.xcframework \
  libvlc.xcframework.zip && shasum -a 256 libvlc.xcframework.zip > libvlc.xcframework.zip.sha256 && cd ..
git switch cobiplayer-lgpl && git merge --no-ff <work-branch>   # README already names the release
git push origin cobiplayer-lgpl
gh release create libvlc-YYYYMMDD --repo c0b1-dev/SwiftVLC-LGPL \
  --target "$(git rev-parse cobiplayer-lgpl)" --title libvlc-YYYYMMDD --notes "Patches 0001, 0003–0008 …" \
  Vendor/libvlc.xcframework.zip Vendor/libvlc.xcframework.zip.sha256
```

1. **Before the merge**, the warning at the top of this README names the new release, so the
   tagged tree is right about itself.
2. **Merge, push, release** as above, pushing only with the owner's go. The release targets the
   **full** merge SHA. It becomes the repository's "latest" release, which `setup-dev.sh` without
   a tag downloads.
3. **In Cobi Player's `ci_scripts/engine.env`**: `LIBVLC_RELEASE`, `LIBVLC_SHA256` (the value in
   the `.sha256` asset), `SWIFTVLC_COMMIT` = the full 40-character merge SHA, and rewrite its
   comment that names the commit the current release is tagged at.
4. **Dry-run** `ci_post_clone.sh` with `CI_PRIMARY_REPOSITORY_PATH` set to a scratch folder. It
   fetches `SWIFTVLC_COMMIT` from GitHub, so it only works after the push.
5. Remove the zip from `Vendor/`. It stays under GitHub's 2 GB asset limit (about 1.5 GB).

### Upstream: `release.sh`

Releases advance `main`: `release.sh` rewrites `Package.swift` to the new remote xcframework URL + checksum, pins the Showcase app to that exact SwiftVLC version, tags that commit, uploads the zip as a GitHub Release asset, and then pushes `main` to that same commit. `setup-dev.sh` is what flips a working checkout back to local sources for day-to-day development.

```bash
./scripts/build-libvlc.sh --all          # produces Vendor/libvlc.xcframework
./scripts/release.sh X.Y.Z --dry-run     # strip + zip + checksum, no push
./scripts/release.sh X.Y.Z               # cut the release
```

What `release.sh` does:

1. Verifies all eight platform slices are present in the xcframework.
2. Copies it to a temp dir, strips debug symbols, zips with `ditto`.
3. Computes SHA-256 via `swift package compute-checksum`.
4. Rewrites `Package.swift` to the remote URL and checksum, and pins the Showcase app to `SwiftVLC` exact version `X.Y.Z`.
5. Commits that change and tags it as `vX.Y.Z`.
6. Pushes the tag first so GitHub can attach the release asset to that exact commit.
7. Uploads the zip to a new GitHub Release.
8. Pushes `main` to the same commit, so `main` always references the latest published xcframework and Showcase package version.

Preflight refuses non-`main` branches, uncommitted changes in `Package.swift` or the Showcase project, pre-existing local or remote tags, and unauthenticated `gh`. If a pre-commit rewrite fails, the script restores `Package.swift` and the Showcase project before exiting. If the tag push succeeds but a later step fails, `origin/main` is still untouched; finish the GitHub Release (or delete the tag) before retrying.

## Architecture

For internals, including module design, C interop, the concurrency model, the event system, memory management, and the PiP rendering pipeline, see **[ARCHITECTURE.md](ARCHITECTURE.md)**.

## License

MIT. See [LICENSE](LICENSE).

libVLC is licensed under [LGPLv2.1](https://www.gnu.org/licenses/old-licenses/lgpl-2.1.html). Static linking may have licensing implications. See the [VLC licensing FAQ](https://www.videolan.org/legal.html).

## Acknowledgments

SwiftVLC stands on the work of the [VideoLAN](https://www.videolan.org/) community. VLC and libVLC represent decades of media playback work by hundreds of contributors.

Thanks also to [VLCKit](https://code.videolan.org/videolan/VLCKit) for establishing libVLC on Apple platforms.
