# Barebones mGBA Multi for Apple TV

This reproducible build kit creates an unsigned, device-only Apple TV IPA with
RetroArch 1.22.2 and one custom core: **mGBA Multi 0.1.0**. The clean first
version deliberately limits its scope to running one GBA ROM in one, two, or
three independent instances.

The source revisions are pinned. The kit contains no games, BIOS files,
certificates, provisioning profiles, or precompiled application.

## Version 0.1.0 contract

- One to three GBA instances; controller ports 1 through 3 map permanently to
  players 1 through 3.
- Stable, aspect-correct native layouts: one screen at 240x160, two side by
  side at 480x160, or two above one centered screen at 480x320.
- Player 1 runs on RetroArch's libretro caller thread. Players 2 and 3 use
  bounded, persistent pthread workers when **Execution** is set to
  **Parallel**. No frame queue or run-ahead is permitted; one `retro_run` call
  advances each active instance by exactly one frame before output is emitted.
- **Sequential** execution remains available as an A/B diagnostic and as the
  automatic fallback if a worker cannot start.
- Audio from every active instance is drained after each frame into fixed-size
  queues, normalized to 65536 Hz with a rational frame accumulator, mixed once,
  and submitted through one libretro callback.
- One aggregate RetroArch save-RAM region contains three fixed player slices,
  so player number, screen placement, controller port, and save data cannot
  exchange identities across restarts.
- No link cable, per-instance speed control, subsystems, save states, rewind
  implementation, background autosave thread, or stock mGBA control core.

## GitHub Actions build

1. Put this folder at the root of a GitHub repository.
2. Open **Actions > Build unsigned Apple TV IPA**.
3. Choose **Run workflow**.
4. Download **RetroArchTV-mGBA-Multi-unsigned**.

The artifact contains the IPA, its SHA-256 checksum, and a build manifest. The
workflow uses a GitHub-hosted macOS runner because the device build needs Xcode
and the tvOS SDK. Its GitHub run number becomes `CFBundleVersion`, allowing a
new build to update an earlier installation.

## Local Mac build

Requirements are macOS, Xcode with the Apple TV device SDK, CMake, Git, Zip,
and Unzip. Run:

~~~sh
chmod +x scripts/*.sh
./scripts/build-unsigned-ipa.sh
~~~

The output is:

~~~text
dist/RetroArchTV-mGBA-Multi-1.22.2-core-0.1.0-unsigned.ipa
~~~

To fetch, verify, patch, and stage the pinned sources without invoking Xcode:

~~~sh
./scripts/build-unsigned-ipa.sh --prepare-only
~~~

The build enables only `mgba_multi_libretro`: `BUILD_LIBRETRO_MULTI=ON`, stock
`BUILD_LIBRETRO=OFF`, GBA enabled, and GB/GBC disabled. It removes stale stock
mGBA modules before the RetroArch Xcode build and verifies that no stock mGBA
framework enters the app. Before cross-compiling, it runs the native layout,
bounded-FIFO, exact audio-cadence, rate-transition, and RTC-container tests.

## Install and use

The IPA has no distribution signature or provisioning profile. Sign it with
your Apple developer identity and a tvOS provisioning profile, then install it
with your normal sideloading tool. Nested frameworks are signed ad hoc so the
signer can replace those signatures consistently. The optional Top Shelf
extension is removed to avoid a second App ID and provisioning profile.

The default identity is:

| Property | Value |
| --- | --- |
| Home-screen name | `mGBA Multi` |
| Bundle identifier | `com.mgbamulti.RetroArchTVBarebones` |
| Local build number | `1` |
| Minimum system | tvOS 13.0 |

Override the bundle identifier when necessary:

~~~sh
BUNDLE_ID=com.yourname.mgbamulti ./scripts/build-unsigned-ipa.sh
~~~

After installation, load a legally obtained `.gba` file with **Nintendo - Game
Boy Advance (mGBA Multi)**. In **Quick Menu > Core Options**, choose one, two,
or three instances and choose Parallel or Sequential execution. Close and
reload content after changing either option. Assign controllers to RetroArch
ports 1, 2, and 3.

The selected ROM is cloned into each active instance. Version 0.1.0 does not
load different ROMs into different screens. Do not use RetroArch save states
with this core; battery-backed in-game saves use the aggregate `.srm` region.

## Package validation

The build fails unless the IPA has the expected bundle ID, display name, build
number, `APPL` package type, AppleTVOS platform, Apple TV device family, tvOS
minimum version, executable permissions, arm64 device binaries, and exact core
framework install name. It also checks all nested framework and dylib
signatures, required libretro exports, and the required `pthread_create`
reference.

The validator rejects a stock mGBA framework, mGBA's `mCoreThread`, link-cable
symbols, removed link/speed/subsystem strings, PlugIns and app extensions,
provisioning profiles, an app-level Xcode signature, ROMs, AppleDouble files,
and unexpected IPA top-level entries.

## Pinned sources

| Component | Revision |
| --- | --- |
| RetroArch | 1.22.2 / `69a4f0ea1e8aaf442ae4858f2e7f2b31a1776576` |
| libretro/mGBA base | `7a12d6d4b9acb14c0ae62c9166b6a2f3d08007f6` |
| mGBA Multi | core version 0.1.0 |
| Device architecture | arm64 tvOS |

See [LICENSES.md](LICENSES.md) for source and redistribution obligations.

## Troubleshooting

- If the Apple TV SDK is missing, open Xcode once, install the tvOS platform,
  and verify `xcode-select -p` points to that Xcode.
- If a patch is neither applicable nor already applied, remove only the kit's
  `.work/sources` directory and rerun the build. Do not silently substitute a
  newer source revision.
- If installation succeeds but no app appears, confirm the signer used a tvOS
  profile matching the final bundle identifier. The packaged app intentionally
  contains no Top Shelf extension or embedded profile.
- For performance comparison, test one instance in both Parallel and
  Sequential modes with RetroArch run-ahead, preemptive frames, and rewind
  disabled. The core never sleeps, waits for display refresh, or accumulates a
  frame backlog internally.
