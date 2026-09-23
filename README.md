# RetroArchTV + mGBA Multi build kit

This kit builds an unsigned, device-only Apple TV IPA containing RetroArch
1.22.2 and the custom mGBA Multi libretro core. The core renders one, two, or
three emulators in a single horizontal RetroArch view, keeps independent save
files, and can connect compatible games through local emulated link support.

The source is fully pinned and the resulting IPA contains only the custom mGBA
Multi core. No games, BIOS files, certificates, provisioning profiles, or
precompiled app are included.

## Fastest route: GitHub Actions

1. Put this entire folder in a GitHub repository.
2. Open the repository's Actions tab.
3. Select **Build unsigned Apple TV IPA**.
4. Choose **Run workflow**.
5. Download the **RetroArchTV-mGBA-Multi-unsigned** artifact when it finishes.

The artifact contains the IPA, its SHA-256 checksum, and a build manifest. The
workflow uses a GitHub-hosted macOS runner because Apple TV binaries require
Xcode and the tvOS SDK.

## Build on a Mac

Requirements:

- macOS with Xcode selected by `xcode-select`
- the Apple TV device SDK
- CMake, Git, Zip, and Unzip
- internet access to fetch the two pinned source repositories

Run:

~~~sh
chmod +x scripts/*.sh
./scripts/build-unsigned-ipa.sh
~~~

The result is written to:

~~~text
dist/RetroArchTV-mGBA-Multi-1.22.2-core-0.1.1-unsigned.ipa
~~~

The script first validates the source revisions and patches, builds the custom
core for arm64 tvOS, embeds it as a framework in RetroArchTV, adds the custom
core metadata to `assets.zip`, packages the app as an IPA, and validates the
archive and Mach-O platform markers.

To fetch and patch the sources without invoking Xcode:

~~~sh
./scripts/build-unsigned-ipa.sh --prepare-only
~~~

## Signing and installation

The output has no Apple distribution signature or provisioning profile.
Before installation, sign the IPA with your own Apple developer identity/team
using your normal tvOS sideloading workflow. The nested core framework is
ad-hoc signed during packaging so a signing tool can replace all signatures
consistently.

The default bundle identifier is `com.mgbamulti.RetroArchTV`. Override it
when building if your signing setup requires a different App ID:

~~~sh
BUNDLE_ID=com.yourname.RetroArchTV ./scripts/build-unsigned-ipa.sh
~~~

The minimum deployment target defaults to tvOS 13.0:

~~~sh
TVOS_DEPLOYMENT_TARGET=15.0 ./scripts/build-unsigned-ipa.sh
~~~

## Using mGBA Multi

1. Sign and install the IPA on Apple TV.
2. Import legally obtained GB, GBC, or GBA content into RetroArch.
3. Select the **Nintendo - Game Boy Advance / Color (mGBA Multi)** core.
4. Open **Quick Menu > Core Options**.
5. Set **Instances** to 1, 2, or 3.
6. Set **Local link cable** on or off.
7. Close and reload the content after changing either option.
8. Assign controllers to RetroArch input ports 1 through 3.

Normal **Load Content** duplicates one selected ROM across the configured
instances. To run different games or versions, use **Load Subsystem** and pick
either **mGBA Link Cable (2 ROMs)** or **mGBA Link Cable (3 ROMs)**.

## Save layout

| Player | Save file |
| --- | --- |
| 1 | RetroArch's normal `<content>.srm` |
| 2 | `<ROM stem>.p2.srm` |
| 3 | `<ROM stem>.p3.srm` |

Player 2 and 3 battery saves are flushed periodically and when content closes.
A RetroArch save state stores all active instances together and must be loaded
with the same instance count.

## Link behavior

- GBA link emulation supports all active instances, up to three.
- GB/GBC link emulation connects players 1 and 2. A third GB/GBC instance can
  run beside them but is not linked because that cable protocol has two peers.
- All linked instances must use the same hardware family.
- Link support is local to the core and is separate from RetroArch netplay.
- Compatibility still depends on the games using mutually compatible link
  protocols.

## Pinned source

| Component | Revision |
| --- | --- |
| RetroArch | 1.22.2 / `69a4f0ea1e8aaf442ae4858f2e7f2b31a1776576` |
| mGBA base | `3a5bc24629867576b0fb576a5d5a21d3b3d6b576` |
| mGBA Multi patch | core version 0.1.1 |
| tvOS architecture | arm64 device |

See [LICENSES.md](LICENSES.md) for licensing and source obligations.

## Troubleshooting

- **Apple TV SDK missing:** open Xcode once, install the tvOS platform when
  prompted, then make sure `xcode-select -p` points to that Xcode.
- **Patch is neither applicable nor already applied:** remove only the
  kit's `.work/sources` directory and run again. Do not substitute newer
  source revisions without reviewing the patches.
- **Signing or installation fails:** the produced IPA is intentionally
  unsigned. Use a tvOS-capable signer and a provisioning profile matching the
  final bundle identifier.
- **Only one game is shown multiple times:** that is the normal Load Content
  behavior. Use Load Subsystem to select separate ROMs.
- **Link does not start:** enable Local link cable, use the same hardware
  family, load link-compatible games, and reload content.
