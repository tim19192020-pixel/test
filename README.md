# Barebones mGBA Multi for Apple TV

This reproducible build kit creates an unsigned, device-only Apple TV IPA with
RetroArch 1.22.2 and one custom core: **mGBA Multi 0.3.0**. It builds on the
stable linkless core while keeping its scope to one GBA ROM in one, two, or
three independent instances.

The source revisions are pinned. The kit contains no games, BIOS files,
certificates, provisioning profiles, or precompiled application.

## Version 0.3.0 contract

- One to three GBA instances; controller ports 1 through 3 map permanently to
  players 1 through 3.
- Stable, aspect-correct native layouts: one screen at 240x160, two side by
  side at 480x160, or two above one centered screen at 480x320.
- Player 1 runs on RetroArch's libretro caller thread. Players 2 and 3 use
  bounded, persistent pthread workers when **Execution** is set to
  **Parallel**. No frame queue or run-ahead is permitted. At normal speed, one
  `retro_run` call advances every active instance by exactly one frame. Manual
  speed-up loops a bounded one to four frames on the same owner lane and within
  the same worker generation. Dialogue acceleration uses the same synchronous
  path with a hard maximum of 20 frames. Neither mode dispatches extra jobs or
  leaves queued work.
- **Sequential** execution remains available as an A/B diagnostic and as the
  automatic fallback if a worker cannot start.
- **Audio output** selects Player 1, Player 2, Player 3, or Disabled. Only the
  selected instance is converted into a fixed-size queue; other native buffers
  are cleared without copying. Disabled and inactive selections emit silence
  at the same exact 65536 Hz rational cadence so frontend pacing does not
  change.
- Every player has an independent speed target from 1.0x through 4.0x in 0.1x
  increments. R2 on that player's controller toggles only that instance between
  1.0x and its selected target. Every content load starts all players at 1.0x;
  the default target is 2.0x.
- L2 independently toggles a conservative FireRed dialogue assist for that
  player. Its dialogue speed is selectable from 5x through 20x in whole-number
  increments (default 10x), and automatic advancement can be disabled. An
  injected A press lasts exactly one emulated frame and is followed by a forced
  released frame at normal speed.
- Dialogue assist is enabled only for exact, clean English (USA) Pokemon
  FireRed revisions 1.0 and 1.1. It blocks trainer battles, wild encounters,
  battle startup, trainer- and scripted-encounter lead-ins, yes/no prompts,
  multichoice prompts, and every state it cannot positively identify. It only
  arms when the nested post-message script path is proven to contain close,
  release, return, and termination operations. Unsupported ROMs fail closed
  without live-state inspection or injected input.
- One aggregate RetroArch save-RAM region contains three fixed player slices,
  so player number, screen placement, controller port, and save data cannot
  exchange identities across restarts.
- No link cable, subsystems, save states, rewind implementation, background
  autosave thread, or stock mGBA control core.

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
dist/RetroArchTV-mGBA-Multi-1.22.2-core-0.3.0-unsigned.ipa
~~~

To fetch, verify, patch, and stage the pinned sources without invoking Xcode:

~~~sh
./scripts/build-unsigned-ipa.sh --prepare-only
~~~

The build enables only `mgba_multi_libretro`: `BUILD_LIBRETRO_MULTI=ON`, stock
`BUILD_LIBRETRO=OFF`, GBA enabled, and GB/GBC disabled. It removes stale stock
mGBA modules before the RetroArch Xcode build and verifies that no stock mGBA
framework enters the app. Before cross-compiling, it runs the native layout,
independent speed-scheduler, audio-selection, bounded-FIFO, exact
audio-cadence, rate-transition, RTC-container, and fail-closed FireRed dialogue
detector tests.

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
reload content after changing either option. **Audio output** and the three
player speed targets can be changed while content is running. Assign
controllers to RetroArch ports 1, 2, and 3; press that controller's R2 button
once to enable its target speed and again to return only that player to 1.0x.
Holding R2 does not repeatedly toggle.

For either exact supported FireRed ROM, press a player's L2 button once to
enable dialogue assist for only that instance and again to disable it. Set
**FireRed dialogue speed (L2 toggle)** from 5x through 20x and use **FireRed
dialogue auto-advance** to enable or disable automatic page/final advancement.
The default is 10x with auto-advance enabled. The supported ROM SHA-1 values
are:

- FireRed English (USA) 1.0:
  `41cb23d8dccc8ebd7c649cd8fbb58eeace6e2fdc`
- FireRed English (USA) 1.1:
  `dd5945db9b930750cb39d00c84da8571feebf417`

Every other revision, translation, ROM hack, and patched image reports the
feature unavailable when L2 is pressed. During recognized dialogue, the core
first proves that every nested return after the message only closes/releases
the message and terminates the script. It rechecks all guards before every
accelerated frame and returns immediately to normal scheduling if a battle,
encounter, choice, side-effecting continuation, or unknown state appears. The
configured multiplier is a target and may be limited by available Apple TV
processing time.

The selected ROM is cloned into each active instance. Version 0.3.0 does not
load different ROMs into different screens. Do not use RetroArch save states
with this core; battery-backed in-game saves use the aggregate `.srm` region.

## Package validation

The build fails unless the IPA has the expected bundle ID, display name, build
number, `APPL` package type, AppleTVOS platform, Apple TV device family, tvOS
minimum version, executable permissions, arm64 device binaries, and exact core
framework install name. It also checks all nested framework and dylib
signatures, required libretro exports, and the required `pthread_create`
reference.

The validator requires the audio selector, all three speed-target options, the
R2 speed descriptor, both FireRed dialogue options, and the L2 dialogue
descriptor. It rejects a stock mGBA framework, mGBA's
`mCoreThread`, link-cable symbols, removed link/subsystem strings, PlugIns and
app extensions, provisioning profiles, an app-level Xcode signature, ROMs,
AppleDouble files, and unexpected IPA top-level entries.

## Pinned sources

| Component | Revision |
| --- | --- |
| RetroArch | 1.22.2 / `69a4f0ea1e8aaf442ae4858f2e7f2b31a1776576` |
| libretro/mGBA base | `7a12d6d4b9acb14c0ae62c9166b6a2f3d08007f6` |
| mGBA Multi | core version 0.3.0 |
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
