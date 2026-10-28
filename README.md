# MacStats

[Tiếng Việt](README.vi.md) | **English** | [简体中文](README.zh.md)

A native Swift app for monitoring your Mac from the menu bar, with MacFan integrated as **Fan Control** in the same application.

![MacStats menu bar monitor](screenshot.png)

## Features

- CPU usage, memory usage, upload/download speeds, and CPU temperature in the menu bar.
- CPU average, hottest CPU sensor, and battery temperature where available.
- Top CPU and memory consumers, with helper processes grouped under their parent app.
- Configurable display columns, Celsius/Fahrenheit, average/hottest menu bar temperature, and 1/2/5-second monitoring intervals.
- Launch at login, an Activity Monitor shortcut, and release update controls.
- **Fan Control:** CPU/GPU temperatures, current and target fan RPM, fixed RPM, editable CPU curves, Quiet/Balanced/Cool presets, and up to three minutes of CPU temperature history.
- Vietnamese, English, and Simplified Chinese in the Fan Control dashboard. The main monitoring menu uses English.

## Requirements

| Component | Requirements |
| --- | --- |
| System monitoring | macOS 11+, Intel or Apple Silicon; sensor availability depends on the model |
| Fan Control | macOS 14+, Apple M4 family; the inherited sensor map was validated on Mac mini M4, other models remain unverified |
| Changing fan settings | Install the bundled privileged helper and authenticate with macOS |
| Building | macOS with Xcode Command Line Tools and a macOS 14+ SDK; Python 3 for icon generation |

The monitor and helper are built as universal `arm64` + `x86_64` binaries. Fan Control is disabled on unsupported systems; the monitor remains available. The project uses system frameworks and does not require an Xcode project or third-party Swift packages.

## Build and run

Build from this repository to use the integrated Fan Control feature:

```sh
git clone https://github.com/huybedev/mac-stats.git
cd mac-stats
./build.sh
open MacStats.app
```

To build, replace `/Applications/MacStats.app`, and launch it in one step, run from the checkout:

```sh
./install.sh
```

This requires write access to `/Applications`. A local `install.sh` builds the local source; it does not download a release. The app stays in the menu bar without a Dock icon. Left- or right-click its display to open the menu.

## Use Fan Control

1. Choose **Fan Control…** in the MacStats menu. Temperatures and RPM can be monitored without the helper.
2. Choose **Install helper** and complete the macOS administrator prompt to enable control.
3. Select **macOS automatic**, **CPU temperature**, or **Fixed RPM**. Edit the curve or target, then click **Apply**. Configuration is saved after a successful apply.
4. Click **Return to macOS** to release control. Closing the window keeps MacStats and fan control running; quitting requests a return to macOS.

Use **Language** in the dashboard to select Vietnamese, English, or Simplified Chinese. **Launch at Login** remains in the main MacStats menu. **Enable CPU curve on launch** is off by default; enable it after applying a suitable curve. Otherwise, control starts only when you apply settings. After sleep, apply again to resume control.

Curve temperatures use Celsius and the hottest CPU sensor. Each fan's curve percentage maps to its own hardware range: 0% is minimum RPM, 100% is maximum RPM, with linear interpolation between points. Cooling demand rises immediately and decreases by at most 150 RPM per two-second cycle. Fixed RPM is also bounded by each fan's limits. The dashboard refreshes every two seconds independently of the monitoring interval.

### Helper and recovery

The helper uses a separate XPC service with bounded status, configure, and release operations. The app and helper verify each other's code signatures. After replacing or updating MacStats, choose **Update helper** to synchronize the trusted signatures. This helper is separate from standalone MacFan; return MacFan or another fan utility to Auto before switching.

CPU or GPU at 90°C requests maximum speed in either custom mode. Quit, disconnect, a heartbeat missing for more than 12 seconds, sensor/read/write failures, and sleep trigger attempts to return control to macOS. A recovery journal allows retries after failed restoration or helper restart. These mechanisms do not establish guarantees for firmware failures or power loss. Real fan writes, sleep/wake, and induced overheating have not been verified for this integration.

Installed helper files:

```text
/Library/PrivilegedHelperTools/com.openhoangnc.macstats.FanHelper
/Library/LaunchDaemons/com.openhoangnc.macstats.FanHelper.plist
/Library/Application Support/MacStats/FanControl/
```

Choose **Remove helper…** in the dashboard to remove it while retaining monitoring. If restoration cannot be confirmed, the uninstaller retains the helper and journal so recovery can be retried. Local builds use ad hoc signing and are not notarized by Apple.

## Updates

Release builds check for updates daily. **Install Updates Automatically** controls automatic installation; **Check for Updates…** checks manually. Local builds carry version `0.0.0` and never check automatically.

The download path in `install.sh`, the updater, and the **GitHub Repository** menu item still point to the upstream [openhoangnc/mac-stats](https://github.com/openhoangnc/mac-stats). They do not track this fork's Fan Control changes. Use the source build above to retain this integration; manually installing an upstream release can replace it.

## Uninstall

From this checkout, run either:

```sh
./uninstall.sh
# or
./install.sh --uninstall
```

These scripts target `/Applications/MacStats.app`, stop the current user's app, unregister login startup, remove an installed MacStats fan helper with administrator authentication, delete the app, and clear that user's preferences. If helper recovery fails, removal stops and its recovery files are retained. For a build kept outside `/Applications`, remove the helper in the dashboard, disable **Launch at Login**, quit, and delete that app bundle.

## Tests and command-line options

```sh
bash test.sh
```

This runs 27 behavioral tests with simulated hardware, plus shell syntax and plist checks. Tests cover validation, curve interpolation, RPM limits, the 90°C override, ownership, watchdog/disconnect recovery, sensor and firmware errors, and the recovery journal. They do not write to real fans. The integrated app has also passed a universal build, signature verification, UI checks, and read-only sensor checks on M4; these do not establish live fan-control coverage.

| Command or flag | Behavior |
| --- | --- |
| `open MacStats.app --args --fan-control` | Open Fan Control at app launch on a supported Mac; if MacStats is already running, open it from the menu |
| `MacStats.app/Contents/Resources/MacStatsFanHelper --probe` | Print a read-only JSON snapshot of temperatures and fans |
| `--cleanup-login-item`, `--uninstall-login-item`, `--uninstall` on the app binary | Unregister login startup and exit; these flags do not remove the app or fan helper |

## Releases

[`.github/workflows/release.yml`](.github/workflows/release.yml) builds and publishes `MacStats.zip` on a `v*` tag push, manual dispatch, or a `main` push containing `[deploy-prod]`. A normal push does not publish a release; Markdown-only pushes are excluded. The workflow stamps the version, builds the universal app and helper, and attaches the archive to a GitHub Release.

## Credits and license

This fork builds on [MacStats](https://github.com/openhoangnc/mac-stats) and integrates the local MacFan implementation. The fan SMC implementation includes work based on Stats under MIT; its attribution and license are preserved in [FanControl/Resources/Stats-LICENSE.txt](FanControl/Resources/Stats-LICENSE.txt) and bundled with the app.
