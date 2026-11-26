# Third-Party Notices

This repository contains or derives from the following projects:

## P4-CAN Universal Unlock

- Upstream: https://github.com/06066060606060/P4can-universal-unlock
- License: GNU GPL v3.0
- The firmware sources under `build/firmware-build/P4-CAN-Universal-*` are modified builds of this project. The strobe patches, Chinese dashboard build, and GPIO notes are documented in `build/firmware-build/3.35.3-爆闪移植.md`.

## T2CAN Universal Unlock

- Upstream: https://github.com/06066060606060/t2can-universal-unlock
- License: GNU GPL v3.0
- The app supports this firmware's two-bus layout (MCP2515 + TWAI) and its
  `/api/lab/fsd/*`, `/api/lab/service-mode/*` routes. No firmware source is
  bundled in this repository.

## SwiftPieces

- Components under `P4CANCompanion/SwiftPieces`
- License: MIT with Commons Clause (original copyright headers retained in each file).

## Vehicle imagery

- Tesla Model 3 / Model Y / Model X side-view renders: StickPNG
  (https://www.stickpng.com/cat/transport/cars/tesla), free for personal use.
- Tesla Model S side-view render: SeekPNG (https://www.seekpng.com/), personal use.
- Tesla Model Y L, new Model Y (Juniper) and new Model 3 (Highland) renders: provided by the project owner.
- Status page vehicle renders by trim, paint and wheel: loaded at runtime from Tesla's public configurator
  image service (static-assets.tesla.cn) and cached on the device; they are not bundled in this repository.
- Tesla, Model 3, Model Y, Model S and Model X are trademarks of Tesla, Inc.
  This project is not affiliated with, endorsed by, or sponsored by Tesla.
- These images are bundled for personal, non-commercial use only.
  Remove them before any commercial distribution.

## Tesla / vehicle disclaimer

This project is not affiliated with, endorsed by, or supported by Tesla, Inc.
