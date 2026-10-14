<!-- source_hash: 83c0405962dd -->
# krkrz_ios — Kirikiri Z for iOS

[日本語](README.md) | English

A wrapper repository for running Kirikiri Z (krkrz) on iOS / iPadOS. It generates an Xcode project
with CMake's Xcode generator and builds it, and uses SDL3 for the system layer.

- The engine and plugin sources come from [krkrz_dev](https://github.com/wamsoft/krkrz_dev) through
  `KRKRZ_BASE`. This repository holds only the iOS-specific build definitions and packaging
- The per-title settings (`ios-config.json`) and assets can live in a separate folder (the project
  folder). This repository can also be built on its own as the bundled sample
- `cmake` (plugin configuration) and `assetPack` (asset collection) share their format with
  krkrz_android / krkrz_linux / krkrz_gdk / krkrz_web. iOS cannot `dlopen`, so every plugin is built in statically

## Requirements

- macOS and Xcode 15 or later (including the Command Line Tools)
- CMake 3.24 or later
- Python 3 (used by the generator scripts such as `scripts/gen-config.py`)
- [vcpkg](https://github.com/microsoft/vcpkg) — set the environment variable `VCPKG_ROOT` to where it is installed
- [krkrz_dev](https://github.com/wamsoft/krkrz_dev) — clone it next to this repository
- For device builds, an Apple Developer Team ID (`DEVELOPMENT_TEAM=XXXXXXXXXX` in `local.mk`)

## Setup

Clone [krkrz_dev](https://github.com/wamsoft/krkrz_dev) **at the same level** as this repository
(the same layout as krkrz_android / krkrz_web).

```bash
mkdir kirikiri && cd kirikiri
git clone --recursive https://github.com/wamsoft/krkrz_dev.git
git clone https://github.com/wamsoft/krkrz_ios.git
cd krkrz_ios
make run
```

```
kirikiri/            ← KRKRZ_BASE (default = the parent folder of this repository)
├── krkrz_dev/       ← engine and plugins
└── krkrz_ios/       ← this repository
```

To use a krkrz_dev in another location, set the environment variable `KRKRZ_BASE` (the **parent**
folder of krkrz_dev). The engine changes for iOS are in the develop branch of krkrz_dev (from 2026-10 on).

## Building and running

```bash
make build                 # Debug build for the Simulator (the first time takes a while to build the vcpkg dependencies)
make run                   # install on the running Simulator and start it
make run SIM_DEVICE=<UDID> # choose the Simulator (booted if not running). List: xcrun simctl list devices available
make build SDK=device DEVICE=<UDID>   # for a device (UDID from xcrun xctrace list devices)
make run SDK=device DEVICE=<UDID>     # install on the device and start it
make xcode                 # open the generated Xcode project (for the debugger)
make ipa                   # Release build for distribution (no REPL) → build/ios/ipa/*.ipa  → docs/release.md
make ipa EXPORT_METHOD=app-store-connect   # for App Store Connect / TestFlight submission
make distclean             # remove build/ios

make build PROJECT_DIR=/path/to/mygame     # build your own project folder
```

After updating krkrz_dev (src/core), run `make configure` (`make configure SDK=device` for a device)
before building. `make build` does not regenerate the Xcode project when it already exists, so source
files added to or removed from the engine are not picked up and the added files are not linked
(resulting in undefined-symbol link errors).

| Variable | Meaning |
|---|---|
| `SDK` | `simulator` (default) / `device` |
| `CONFIG` | `Debug` (default) / `Release` |
| `DEVICE` | The device UDID (with `SDK=device`) |
| `SIM_DEVICE` | The Simulator UDID (default `booted` = the running one) |
| `REPL` | Pass `-replweb=<port>` at startup ([REPL](#repl-for-development)) |
| `EXPORT_METHOD` | Export method of `make ipa` (`development` (default) / `release-testing` / `app-store-connect`) |

Build output:

```
${PROJECT_DIR}/build/ios/
├── generated/          # output of gen-config.py (app.cmake, myapp.cmake, assets/, Assets.xcassets)
├── simulator-<arch>/   # Xcode project + build products (krkrz/Debug-iphonesimulator/krkrz.app). arch is the host CPU
├── device-arm64/
├── generated-dist/     # generated files for the distribution build (make archive / ipa)
├── dist/               # Xcode project of the distribution build
├── archive/            # krkrz.xcarchive
└── ipa/                # exported ipa
```

## Project folder (PROJECT_DIR)

This repository is a shared build system; the settings and assets of the title you build can live
in a separate folder.

| Variable | Meaning |
|---|---|
| `BUILD_SYSTEM_DIR` | The root of this repository. The Makefile determines it automatically |
| `PROJECT_DIR` | The project folder. `${PROJECT_DIR}/ios-config.json` is read and output goes to `${PROJECT_DIR}/build/ios/`. When not set, this repository itself (the sample) |
| `KRKRZ_BASE` | The parent folder of krkrz_dev. Defaults to the parent folder of this repository |

- Relative paths in `ios-config.json` are based on `PROJECT_DIR`. To point inside this repository, write `${BUILD_SYSTEM_DIR}/...`
- Environment settings shared across titles (such as `DEVELOPMENT_TEAM`) go in `local.mk` at the root of this repository (not tracked by git)

## ios-config.json

Specifies the bundle ID, version, supported devices, screen orientations, plugins and assets. The file
at the root of the repository is both the sample and the template. A full example and each key are
described in [docs/ios-config.md](docs/ios-config.md) (in Japanese).

| Key | Description |
|---|---|
| `bundleId` / `displayName` | Bundle ID and the name on the home screen |
| `version` / `build` | Display version (`CFBundleShortVersionString`) and build number (`CFBundleVersion`) |
| `deploymentTarget` / `devices` / `orientations` | Minimum iOS version, supported devices (iPhone / iPad), screen orientations |
| `graphics` | `gles` (default; OpenGL ES, GL features such as Canvas / Shader are available) / `metal` (SDL_Renderer only) |
| `repl` | Whether to build in the browser REPL (`-replweb`). Distribution builds never include it, regardless of this setting |
| `icon` | App icon (1024x1024 PNG). [docs/icon.md](docs/icon.md) |
| `ipa.baseName` | Output file name of `make ipa` |
| `infoPlist` / `entitlements` | Extra Info.plist keys, entitlements |
| `cmake` | Plugins to build in (format shared by the wrappers). All are built in statically |
| `assetPack` | Asset collection (format shared by the wrappers). The result is copied to the root of the app bundle |

For the format of `cmake` / `assetPack` / `${...}` path expansion, see
[Shared settings of the platform wrappers](https://wamsoft.github.io/krkrz_dev/en/topics/core/platform_config/)
on the documentation site.

## First-time preparation for device builds

1. Sign in with your Apple ID in Xcode > Settings > Accounts, and **install the iOS platform in Settings > Components**
   (`xcodebuild -downloadPlatform iOS` also works). It is needed for builds that specify a device
2. Write your Team ID in `local.mk`: `DEVELOPMENT_TEAM=XXXXXXXXXX`
3. Enable Developer Mode on the iPhone (Settings > Privacy & Security > Developer Mode)
4. `make build SDK=device DEVICE=<UDID>` — automatic signing registers the connected device with the Team and creates a profile
5. If signing fails with `errSecInternalComponent` (a build from a terminal / agent cannot show the
   keychain permission dialog), run the following once in Terminal.app:
   `security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k '<login password>' ~/Library/Keychains/login.keychain-db`
6. On first launch, trust the developer on the iPhone in Settings > General > VPN & Device Management

`make build SDK=device` without `DEVICE` becomes a `-target` build and does not register the device
(it signs with the already registered Team / profile if there is one).

## Distribution builds and App Store Connect

`make archive` / `make ipa` create a Release build with the engine's `MASTER` configuration (no REPL),
in a build directory separate from the development build. Preparation, export methods
(`development` / `release-testing` / `app-store-connect`), uploading to App Store Connect and the
pre-submission checklist are in [docs/release.md](docs/release.md) (in Japanese).

## REPL (for development)

Builds with `"repl": true` include the engine's browser REPL (`-replweb`, HTTP+SSE).
It listens only when `-replweb=<port>` is passed as a startup argument (all interfaces, IPv6+IPv4).

```bash
make run REPL=8899                                   # Simulator → http://127.0.0.1:8899/
make run SDK=device DEVICE=<UDID> REPL=8899          # device → over USB at http://[<IPv6>]:8899/
```

A device is reached through the IPv6 tunnel that CoreDevice sets up over a USB connection. Look up the
address with `dscacheutil -q host -a name <device name>.coredevice.local` (the device name is the
Hostname in `xcrun devicectl list devices`). Opening it in a browser gives the Console / Watch / Pad
UI. You can also evaluate with `curl -X POST --data '<TJS>' http://[...]:8899/cmd` (results come on the `/events` SSE).
For how to use the REPL, see the engine's `doc/REPL.md` and the skill `krkrz-repl`.

The first time, a permission dialog for local network access may appear (`NSLocalNetworkUsageDescription`
is added to Info.plist automatically when repl is enabled). Distribution builds leave the REPL out automatically.

## Touch input

On iOS the engine converts touch into mouse input (SDL's standard conversion is disabled).

| Gesture | What is sent |
|---|---|
| One-finger tap / drag | Left button press, move and release (the press is held for 100 ms to tell it from two fingers) |
| Two-finger tap (released without moving) | ESC key (back) |
| Two-finger vertical swipe | Mouse wheel (fingers up = scroll down) |

Setting `Window.enableTouch = true` also delivers `onTouch*` events.
`Window.enableTouchMouse = false` stops the conversion to mouse input.

## iOS-specific plugins

`plugins/` holds plugins for iOS only. List a name in `cmake.plugins` of `ios-config.json` to build it in
(`cmake.pluginFolders` must include `${BUILD_SYSTEM_DIR}/plugins`). See [docs/plugins.md](docs/plugins.md) for details.

| Plugin | Contents |
|---|---|
| `virtualpad` | Shows a translucent on-screen gamepad and passes touches on as gamepad input (`VK_PAD*`). Same source as krkrz_android |
| `iosconfig` | Adds a system menu (swipe in from the left edge), a settings screen and a license screen |

## Documentation

The documents under `docs/` are in Japanese.

| Document | Contents |
|---|---|
| [docs/ios-config.md](docs/ios-config.md) | Full example and each key of `ios-config.json`, generated files |
| [docs/plugins.md](docs/plugins.md) | How to use the iOS-specific plugins (virtual pad, system menu) |
| [docs/release.md](docs/release.md) | Distribution builds (Archive / ipa), App Store Connect submission, pre-submission checklist |
| [docs/icon.md](docs/icon.md) | Where to put the app icon, how to set it, image requirements |
| [docs/ios-design.md](docs/ios-design.md) | Design study and implementation history |

The documentation for Kirikiri Z itself is on the [documentation site](https://wamsoft.github.io/krkrz_dev/en/).

## License

This repository (build scripts, tools and templates) is under the [MIT License](LICENSE).

The following, referenced or fetched at build time, follow their own licenses; the license of this
repository does not extend to them.

- The Kirikiri Z engine and plugins (each submodule under krkrz_dev)
- SDL3 (zlib License) and the dependency libraries fetched through vcpkg
- Xcode / the iOS SDK (Apple's license terms)

Include the license notices required in your distribution on the title side, according to the engine,
plugins and libraries you use.
