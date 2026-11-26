# ChiakiKit.xcframework: libchiaki for tvOS

`build-chiaki-xcframework.sh` builds **libchiaki** (the core library of
[chiaki-ng](https://github.com/chiaki-ng/chiaki-ng) `v1.10.1`) and all of its
dependencies as static arm64 libraries for tvOS (minimum tvOS 18.0). It merges
them into one library per platform and packages the result as
`out/ChiakiKit.xcframework`, which Swift can use with `import ChiakiKit`.

## Prerequisites

- **Full Xcode** with the tvOS platform installed (Xcode > Settings > Components),
  selected with:
  `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer`
- Homebrew tools: `brew install cmake ninja pkgconf python git gnupg`
  (CMake 3.24 or newer; CMake 4.x is fine. Python 3.10 or newer.)
- Optional, to check the signature on the chiaki-ng tag:
  `curl -s https://github.com/streetpea.gpg | gpg --import`
  (expected fingerprint `609B7D18288DF6E62624B0694569A5F4961E8ED9`)

The script never uses sudo and installs nothing globally. The Python packages
for the nanopb generator go into a venv at `build/venv`, installed from
`requirements-nanopb.txt` with `--require-hashes`.

## Run

```sh
cd ~/Projects/apple/TVRemotePlay/deps
./build-chiaki-xcframework.sh            # tvOS Simulator (arm64) slice only
./build-chiaki-xcframework.sh --device   # Simulator + Apple TV device slices
```

Options: `--clean` (delete build/ and out/), `--clean-all` (also delete src/),
`--jobs N`, `--verbose`. When you run it again, steps that already finished are
skipped. Changing a pinned version or an option rebuilds that step and every
step that depends on it.

## Outputs

| Path | What |
|---|---|
| `out/ChiakiKit.xcframework` | `libChiakiKit.a` and headers for each slice you built |
| `out/ChiakiKit-versions.txt` | Exact versions, hashes and commits that went in |
| `build/logs/*.log` | Full log of each step for each slice |
| `src/` | Verified sources. Downloads are kept in `src/_downloads` |

For each slice the script checks that the merged library:
- is arm64 only,
- targets the right platform, with no object needing more than tvOS 18.0
  (checked with `otool`),
- builds the `ChiakiKit` Clang module and links a small test program that calls
  the main entry points, so missing symbols show up here and not in Xcode.

## Add it to the TVRemotePlay target

1. Run the script with `--device` so both slices are in the XCFramework.
2. In Xcode, drag `deps/out/ChiakiKit.xcframework` into the project navigator.
   Leave "Copy items if needed" off so the target uses the built file in place,
   and tick the **TVRemotePlay** target.
3. Target > General > *Frameworks, Libraries, and Embedded Content*: set
   ChiakiKit.xcframework to **Do Not Embed** (it is a static library). Click
   **+** and add **Security.framework**. CoreFoundation is linked automatically
   through the module map.
4. In Swift:

```swift
import ChiakiKit

final class ChiakiLogBridge {
    var log = ChiakiLog()
    init() {
        chiaki_log_init(&log, 0x1f /* CHIAKI_LOG_ALL */, { level, msg, _ in
            if let msg { print("[chiaki \(level.rawValue)] \(String(cString: msg))") }
        }, nil)
        _ = chiaki_lib_init()
    }
}
```

Notes on calling it from Swift:
- C callbacks must be closures that capture nothing (`@convention(c)`). Pass
  `Unmanaged.passUnretained(self).toOpaque()` as the `user` pointer and get the
  object back inside the callback.
- Fixed-size `char[]` fields, such as `ChiakiConnectInfo.regist_key`, come into
  Swift as tuples. Fill them with `withUnsafeMutableBytes(of:)`.
- The `static inline` setters (`chiaki_session_set_video_sample_cb` and the
  others) can be called from Swift. The variadic `chiaki_log()` cannot.
- Callbacks run on chiaki's own threads, not the main thread.

## What was decided and why

- **OpenSSL 3.5 LTS, not mbedtls.** Certificate-chain repair for PSN only
  exists for OpenSSL (`lib/src/aia_openssl.c`; with mbedtls,
  `holepunch.c` turns it off). chiaki-ng's mbedtls path is also pinned to the
  end-of-life mbedtls 2.28. OpenSSL 3.5.9 has no tvOS Configure targets, so
  `openssl-tvos.conf` adds `tvos64-xcrun` and `tvossimulator-arm64-xcrun`,
  copied from its iOS targets.
- **RUDP (Remote Play over the Internet) is always built in.** In v1.10.1,
  `CHIAKI_ENABLE_RUDP` is declared, but nothing uses it, and `session.c` and
  `ctrl.c` call the RUDP and holepunch code directly. So json-c, miniupnpc,
  libevent and curl are always needed, and there is no `--no-rudp` switch.
  All four build as plain C for tvOS.
- **curl 8.23.0 is built separately**, not from the chiaki-ng curl submodule.
  The submodule is curl 8.11.1 (Dec 2024) and misses two years of security
  fixes. curl is built with OpenSSL plus **Apple SecTrust**
  (`USE_APPLE_SECTRUST`, `CURL_CA_BUNDLE=none`), so HTTPS and WSS to PSN are
  checked against the tvOS trust store. tvOS has no CA bundle file. Only
  http, https, ws and wss are enabled.
- **One patch to chiaki-ng** (`patches/…keep-tvos-deployment-target.patch`):
  its top-level CMakeLists.txt forces `CMAKE_OSX_DEPLOYMENT_TARGET=13.0` on
  every Apple platform. The patch limits that to macOS, so the tvOS 18.0
  target is used.

## Pinned sources and how they are checked

| Component | Version | Check |
|---|---|---|
| chiaki-ng | v1.10.1 | commit `f30da0aaeb96fc0026cc03683153f682352e7d7c`; `git verify-tag` against key `609B7D18288DF6E62624B0694569A5F4961E8ED9` (a warning if the key is not imported) |
| nanopb | 0.4.9.2 (submodule) | commit `160d4f09e5fabb2b66aa2dea32d4f38ace2c4b3f` |
| jerasure | submodule | commit `505ccb4bc69eee8d7ea40a6089a056b99671134f` |
| gf-complete | submodule | commit `fa54a4670a5705c84abf6c24b92b0cd479625478` |
| OpenSSL | 3.5.9 (LTS) | SHA-256 `603f5602e2eef00d77fbd429d34dcd5822bb301757a1bc9cdb24c670f1eb859a` (published `.sha256` file) |
| Opus | 1.6.1 | SHA-256 `6ffcb593207be92584df15b32466ed64bbec99109f007c82205f0194572411a1` (xiph `SHA256SUMS.txt`) |
| curl | 8.23.0 | tag `curl-8_23_0` = commit `3163ec065643ba20709f190111f42c3e1fe95273` (curl publishes no checksums) |
| libevent | 2.1.12-stable | tag commit `5df3037d10556bfcb675bc73e516978b75fc7bc7` (libevent_core only) |
| json-c | 0.18-20240915 | tag commit `41a55cfcedb54d9c1874f2f0eb07b504091d7e37` |
| miniupnpc | 2.3.5 | tag commit `e1db7c47295d38b2b416c892779dae9afa434016` |
| protobuf / grpcio-tools (Python) | 7.36.2 / 1.85.4 | pip `--require-hashes` (`requirements-nanopb.txt`) |

The same pins are set at the top of the script.

## Troubleshooting

- **"SDK appletvsimulator not found"**: install the tvOS platform in Xcode
  (Settings > Components), or run `xcodebuild -downloadPlatform tvOS`.
- **A step fails**: the script prints the last 60 lines of the log. The full
  log is in `build/logs/<slice>-<step>.log`. Use `--verbose` to watch the
  output live.
- **CMake 4 says "Compatibility with CMake < 3.5 has been removed"**: every
  CMake call already passes `CMAKE_POLICY_VERSION_MINIMUM=3.5`. If a step still
  fails this way, make sure `cmake` in PATH is the Homebrew one (`which cmake`).
- **chiaki configure cannot find `PythonInterp`** (a future CMake might remove
  that module): install CMake 3.31 into the venv
  (`build/venv/bin/pip install cmake==3.31.*`) and put `build/venv/bin` first
  in PATH.
- **curl configure: "CoreServices framework not found"**: the script then
  falls back to CoreFoundation by itself. libcurl does not call CoreServices.
- **Xcode: "No such module 'ChiakiKit'"**: clean the build folder
  (Shift-Cmd-K) and check that the XCFramework is in the target's
  *Frameworks, Libraries…* list. If that does not help, add
  `$(BUILT_PRODUCTS_DIR)/include` to *Swift Compiler – Search Paths > Import
  Paths*.
- **Xcode: "building for tvOS, but linking in object file built for tvOS
  Simulator"** (or the other way round): the XCFramework does not have that
  slice. Run the script again with `--device`.
- **Undefined symbols `_SecTrust…` / `_CF…`**: add Security.framework (and
  CoreFoundation.framework) to the target.
- **Tag signature warning**: import the key (see Prerequisites) and run again.
  The commit hash is checked either way.
- **Internet remote play later**: PSN HTTPS and WSS use curl with SecTrust and
  need no CA file. chiaki's extra repair for incomplete certificate chains
  (AIA) only works when curl has a CA file or path. In this build it is
  inactive and logs a warning if a server sends an incomplete chain.

## License note

chiaki-ng is licensed under AGPL-3.0 (with an OpenSSL exception). Linking it
statically is fine for your own use. If you ever distribute the app, the AGPL
applies to it.
