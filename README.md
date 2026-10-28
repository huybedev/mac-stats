# MacStats 📊

> A lightning-fast, native macOS Menu Bar monitor built with Swift. Keep an eye on your CPU usage, RAM consumption, network speeds, and CPU temperature in real time—right at a glance.

🌐 [English](README.md) | [Tiếng Việt](README.vi.md) | [简体中文](README.zh.md) | [日本語](README.ja.md)

![macOS 11.0+](https://img.shields.io/badge/macOS-11.0%2B-blue?logo=apple)
![Swift](https://img.shields.io/badge/Swift-5.0-orange?logo=swift)
![License](https://img.shields.io/badge/License-MIT-green)

![MacStats Screenshot](screenshot.png)


## Fan Control

Open **Fan Control…** from the MacStats menu to use the integrated MacFan dashboard: live CPU/GPU temperatures, fan RPM, fixed RPM, editable CPU curves, Quiet/Balanced/Cool presets, and a three-minute temperature history. The dashboard supports Vietnamese, English, and Simplified Chinese. Launch at login remains in the main MacStats menu; **Enable CPU curve on launch** is configured in Fan Control. Closing this window keeps fan control running in MacStats.

Fan Control requires **macOS 14+ and Apple M4**; the existing monitor still runs on macOS 11+ on Intel and Apple Silicon. The inherited sensor map was tested by MacFan on Mac mini M4; other models are unverified. Install the bundled helper from the dashboard and authenticate with macOS to enable control. Read-only monitoring works without it. After replacing or updating MacStats, use **Update helper** to trust the new app signature. This helper is separate from the standalone MacFan helper; return that app to Auto before switching.

Targets stay within each fan's hardware limits. CPU or GPU at 90°C requests maximum speed. Disconnect, a missed heartbeat, sensor/write failure, sleep, or quitting requests a return to macOS; failed recovery is journaled and retried. These mechanisms have automated tests with simulated hardware; real sleep/wake and induced overheating have not been verified. Control never starts automatically unless you enable the launch option.

Use **Remove helper…** in the dashboard to remove fan control. Both `uninstall.sh` and `install.sh --uninstall` also remove an installed MacStats fan helper, requesting administrator authentication; if recovery fails, they retain it for retries. Helper files use `com.openhoangnc.macstats.FanHelper` under `/Library/PrivilegedHelperTools` and `/Library/LaunchDaemons`, with recovery state under `/Library/Application Support/MacStats/FanControl`.

```sh
bash test.sh                         # behavioral tests with simulated hardware; no fan writes
open MacStats.app --args --fan-control
MacStats.app/Contents/Resources/MacStatsFanHelper --probe  # read-only hardware snapshot
```

The SMC implementation includes work based on Stats (MIT); its license is in `FanControl/Resources/Stats-LICENSE.txt` and is bundled with the app.


---

## ⚡ Quick Start

### 📦 One-Line Download & Install
Just copy and paste this command into your Terminal. It will automatically download, extract, and install **MacStats** directly into your `/Applications` folder:

```bash
curl -fsSL https://raw.githubusercontent.com/openhoangnc/mac-stats/main/install.sh | bash
```

---

### 🗑️ Complete Uninstallation
Want to remove it completely? This command safely stops the app, removes it from your startup items, clears your user preferences, and deletes the app bundle:

```bash
curl -fsSL https://raw.githubusercontent.com/openhoangnc/mac-stats/main/uninstall.sh | bash
```

---

## ✨ Key Features

- 🚀 **Ultra-Lightweight & Blazing Fast**: Written entirely in native Swift, guaranteeing a minimal memory and CPU footprint. No bloated Xcode projects or heavy third-party dependencies.
- 📊 **Triple-Column Menu Bar Display**:
  - **Left (Network)**: Real-time Upload (top) and Download (bottom) speeds. Units scale automatically (`B`, `K`, `M`, `G`), and colors adapt dynamically to bandwidth usage.
  - **Center (CPU/Memory)**: Live CPU load (`%`, top) and RAM usage (`G`, bottom). Smart color thresholds (Green → Yellow → Red) instantly warn you under heavy load.
  - **Right (Temperature)**: CPU temperature (top) — the average, or the hottest sensor if you prefer — and unit (`°C` or `°F`, bottom). Text colors shift dynamically based on heat levels.
- 🔝 **Top Resource Hogs at a Glance**: Opening the menu instantly reveals the apps consuming the most **CPU** and **memory**, ranked in real time. Helper processes (like a browser's many renderers) are rolled up into their parent app, and background system daemons are filtered out—so you only see the apps that actually matter.
- 🌡️ **Temperatures at a Glance**: The menu also lists the **CPU average**, the **CPU hottest** sensor (the reading thermal throttling reacts to), and the **battery** temperature on MacBooks.
- ⚙️ **Quick Settings Menu**: Left or right-click the menu bar icon to access:
  - **Open Activity Monitor**: Jump straight to macOS Activity Monitor for the full, detailed breakdown.
  - **Show Network Speeds**: Toggle the visibility of the network speeds column.
  - **Show CPU Temperature**: Toggle the visibility of the CPU temperature column.
  - **Launch at Login**: Easily toggle automatic startup. (Seamlessly uses macOS 13+ `SMAppService`, with automatic fallbacks to LaunchAgents plist for older systems).
  - **Install Updates Automatically**: On by default. Turn it off to have new versions offered in the menu instead of installed.
  - **Update Interval**: Customize how often data refreshes (1s, 2s, or 5s).
  - **Temperature Unit**: Switch effortlessly between Celsius and Fahrenheit.
  - **Menu Bar Temperature**: Show the CPU average or the hottest CPU sensor in the menu bar.
  - **GitHub Repository**: Direct link to the source code.
  - **Check for Updates…**: Check GitHub for a newer release right now.
  - **Quit MacStats**: Safely close the app.
- 🧠 **Dynamic SMC Temperature Scanning**: On startup, it automatically discovers active SMC temperature sensors for both Intel and Apple Silicon (M1/M2/M3/M4/M5) chips—including efficiency cores, performance cores, and general sensors—to calculate an accurate real-time average and hottest-sensor reading. On Apple Silicon, each sensor's live and peak keys are told apart, and the offset keys that are not real measurements are left out.
- ⚡ **Deep Performance & Memory Optimizations**:
  - Runs entirely as a background accessory (`LSUIElement`). It stays out of your Dock and won't clutter your Command-Tab app switcher.
  - Actively prevents memory fragmentation by calling `malloc_zone_pressure_relief` on startup and every 30 seconds thereafter.
  - Implements a smart 25% timer tolerance, allowing macOS to coalesce background tasks and drastically save battery life.
- 🔄 **Automatic Updates**: Once a day MacStats asks GitHub for the latest release. When there's a newer one, it downloads `MacStats.zip`, checks it (SHA-256 digest, bundle ID, version, code signature), swaps it in place and restarts—never while the menu is open. Builds you compile yourself never update on their own; use **Check for Updates…** to switch one to the release.
- 🤖 **Automated CI/CD Workflows**: A built-in GitHub Actions pipeline automatically compiles the `.app`, increments semantic version numbers, and publishes new GitHub Releases.

---

## 🛠️ CLI Flags & Manual Build
The compiled binary natively supports the following command-line flags for silent management:
- `--cleanup-login-item` / `--uninstall-login-item` / `--uninstall`: Silently unregisters `SMAppService` launch items, removes user LaunchAgent plists, flushes user defaults, and immediately exits.

If you prefer to compile it yourself from source:

1. Clone the repository:
   ```bash
   git clone https://github.com/openhoangnc/mac-stats.git
   cd mac-stats
   ```

2. **Build & install in one step (recommended).** When run from a local
   checkout, `install.sh` detects the source and builds from it instead of
   downloading a release—compiling a universal (Apple Silicon + Intel) binary
   via `build.sh`, installing it to `/Applications`, and launching it:
   ```bash
   ./install.sh
   ```

   Or just build the `.app` bundle in place without installing:
   ```bash
   ./build.sh
   open MacStats.app
   ```

> **Note:** The one-line command in [Quick Start](#-one-line-download--install) downloads the latest prebuilt release, whereas `./install.sh` run from a cloned repo always builds and installs your local source.

---

## 🤖 Continuous Integration & Versioning

The project is fully automated via `.github/workflows/release.yml`.

- **Automatic Version Bumping**: Pushing to the main branch (or triggering manually) automatically bumps the version number (e.g., `v1.0.0` → `v1.0.1`).
- **Automated Releases**: The workflow compiles the native macOS app bundle, compresses it into `MacStats.zip`, and automatically attaches it to a new GitHub Release.

---

## 🧑‍💻 For Developers: Unique Techniques to Learn

This project employs several uncommon and highly optimized techniques for macOS development that you might find interesting:

1. **Zero-Xcode App Bundling**: This app is built entirely without an Xcode project file. Instead, it uses a custom bash script (`build.sh`) that invokes the `swiftc` compiler directly with aggressive size optimizations (`-Osize`, `-wmo`, `-dead_strip`). It then manually constructs the `.app` bundle structure, proving that you can build native macOS UI apps with just a terminal and text editor.
2. **Direct Low-Level C APIs**: To achieve near-zero CPU overhead, the app bypasses high-level `Foundation` wrappers. It directly calls Mach kernel APIs (`host_processor_info`, `host_statistics64`) and BSD socket APIs (`getifaddrs`) from Swift using raw memory pointers.
3. **Zero-Allocation String Parsing**: Inside the network polling loop, instead of allocating a Swift `String` to check if an interface is Ethernet/Wi-Fi (e.g., `name.hasPrefix("en")`), the engine compares raw C-string bytes directly (`namePtr.pointee == 0x65 && namePtr.advanced(by: 1).pointee == 0x6e`). This completely eliminates memory allocation in the high-frequency polling loop.
4. **Dynamic SMC Discovery via IOKit**: Instead of hardcoding temperature sensor keys or using undocumented private frameworks, the app uses IOKit to dynamically probe the System Management Controller (SMC) on startup. It checks a vast array of known Apple Silicon and Intel keys, automatically discovering which ones are active on the host machine.
5. **Active Memory Pressure Relief**: Background apps that run indefinitely often suffer from memory fragmentation. This app actively mitigates this by manually calling low-level memory management functions (like `malloc_zone_pressure_relief`) to aggressively keep the background memory footprint tight.

---

## 📄 License

This project is licensed under the MIT License.
