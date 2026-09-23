# Licensing and source

This kit contains build automation and two source patches. It does not include
ROMs, BIOS images, signing certificates, provisioning profiles, or a compiled
Apple application.

- RetroArch 1.22.2 is fetched from
  <https://github.com/libretro/RetroArch> at commit
  `69a4f0ea1e8aaf442ae4858f2e7f2b31a1776576` and is licensed under
  GPL-3.0-or-later. Its complete license text remains in the fetched source as
  `COPYING`.
- mGBA is fetched from <https://github.com/mgba-emu/mgba> at commit
  `3a5bc24629867576b0fb576a5d5a21d3b3d6b576` and is licensed under MPL-2.0.
  Its complete license text remains in the fetched source as `LICENSE`.
- `patches/mgba-multi.patch`, including the new multi-instance core source,
  is distributed under MPL-2.0.
- `patches/retroarch-unsigned-frameworks.patch` is a small build-script
  modification distributed on the same GPL-3.0-or-later terms as RetroArch.
- The build scripts and workflow authored for this kit may be used, modified,
  and redistributed under the MIT License.

The RetroArch checkout includes third-party components with their own notices.
Review the fetched source tree before redistributing a compiled IPA.
