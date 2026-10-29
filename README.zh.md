# MacStats

[Tiếng Việt](README.vi.md) | [English](README.md) | **简体中文**

使用原生 Swift 编写的 macOS 菜单栏系统监控应用，将 MacFan 集成为同一应用中的 **Fan Control（风扇控制）** 功能。

![MacStats 菜单栏监控界面](screenshot.png)

## 功能

- 在菜单栏显示 CPU 使用率、内存占用、上传/下载速度和 CPU 温度。
- 查看 CPU 平均温度、最高 CPU 传感器温度，以及设备支持的电池温度。
- 查看 CPU 和内存占用最高的应用，并将辅助进程归入所属应用。
- 自定义显示列、摄氏/华氏单位、平均/最高温度，以及 1/2/5 秒的监控刷新间隔。
- 登录时启动、快速打开活动监视器，以及管理发布版本更新。
- **风扇控制：** CPU/GPU 温度、当前及目标 RPM、固定 RPM、可编辑 CPU 温度曲线、安静/均衡/凉爽预设，以及最多三分钟的 CPU 温度历史。
- 风扇控制面板支持越南语、英语和简体中文，主监控菜单使用英语。

## 系统要求

| 组件 | 要求 |
| --- | --- |
| 系统监控 | macOS 11+，Intel 或 Apple Silicon；传感器可用性取决于机型 |
| 风扇控制 | macOS 14+，Apple M4 系列；继承的传感器映射已在 Mac mini M4 上验证，其他机型尚未验证 |
| 更改风扇设置 | 安装随应用提供的特权辅助程序，并通过 macOS 管理员认证 |
| 构建 | 安装 Xcode Command Line Tools 和 macOS 14+ SDK 的 Mac；生成图标需要 Python 3 |

应用和辅助程序均构建为 `arm64` + `x86_64` 通用二进制文件。不支持的系统会禁用风扇控制，系统监控仍可使用。项目使用系统框架，无需 Xcode 工程或第三方 Swift 包。

## 构建与运行

请从本仓库构建，以使用集成的风扇控制功能：

```sh
git clone https://github.com/huybedev/mac-stats.git
cd mac-stats
./build.sh
open MacStats.app
```

如需一步完成构建、替换 `/Applications/MacStats.app` 并启动，请在源码目录运行：

```sh
./install.sh
```

这需要 `/Applications` 的写入权限。从源码目录运行的 `install.sh` 会构建本地源码，不会下载发布版本。应用常驻菜单栏，不显示 Dock 图标。左键或右键点击指标即可打开菜单。

## 使用风扇控制

1. 在 MacStats 菜单选择 **Fan Control…**。无需安装辅助程序即可查看温度和 RPM。
2. 点击 **安装辅助程序**，完成 macOS 管理员认证后启用控制。
3. 选择 **macOS 自动**、**按 CPU 温度** 或 **固定转速**，调整曲线或目标后点击 **应用**。配置在成功应用后保存。
4. 点击 **交还 macOS** 释放控制权。关闭窗口后 MacStats 和风扇控制仍继续运行，退出应用时会请求交还 macOS。

在面板的 **语言** 中选择越南语、英语或简体中文。**Launch at Login** 位于 MacStats 主菜单中。**启动时启用温度曲线** 默认关闭，请在应用合适的曲线后再开启；未开启时，只有应用设置才会开始控制。自定义控制期间，MacStats 防止 App Nap 延迟心跳，同时仍允许系统睡眠。唤醒后重新应用最近成功应用的配置，不会使用未保存的编辑。应用运行期间会保留已应用的配置，睡眠、断线或看门狗触发后，传感器恢复正常且硬件处于自动状态时重试；失败后间隔 30 秒。主动交还 macOS 或退出应用才会取消恢复。

温度曲线使用摄氏度及最高 CPU 传感器温度。百分比按每个风扇自身的硬件范围换算：0% 为最低 RPM，100% 为最高 RPM，节点之间线性插值。散热需求增加时立即提高目标，降低时每两秒最多下降 150 RPM。固定 RPM 同样受每个风扇的硬件范围限制。面板每两秒刷新，独立于主监控刷新间隔。

### 辅助程序与恢复

辅助程序使用独立 XPC 服务，仅提供状态读取、受限配置和释放控制操作。应用与辅助程序相互验证代码签名。替换或更新 MacStats 后，请选择 **更新辅助程序** 以同步受信任签名。它与独立 MacFan 的辅助程序分离；切换前请先将 MacFan 或其他风扇工具设为 Auto。

在两种自定义模式下，CPU 或 GPU 达到 90°C 都会请求最高转速。退出、连接中断、心跳超过 12 秒未收到、传感器/读写故障以及睡眠会触发交还 macOS 的尝试。恢复日志支持在恢复失败或辅助程序重启后重试，但不保证处理固件故障或断电。本次集成尚未验证真实风扇写入、睡眠/唤醒及过热场景。

辅助程序安装文件：

```text
/Library/PrivilegedHelperTools/com.openhoangnc.macstats.FanHelper
/Library/LaunchDaemons/com.openhoangnc.macstats.FanHelper.plist
/Library/Application Support/MacStats/FanControl/
```

选择 **移除辅助程序…** 可仅移除控制功能并保留监控。如果尚未确认控制权交还 macOS，卸载程序会保留辅助程序及日志以继续恢复。本地构建使用 ad hoc 签名，未经 Apple 公证。

## 更新

发布版本每天检查更新。**Install Updates Automatically** 控制自动安装，**Check for Updates…** 用于手动检查。本地构建版本号为 `0.0.0`，不会自动检查更新。

`install.sh` 的下载来源、应用更新器及 **GitHub Repository** 菜单项目前仍指向上游 [openhoangnc/mac-stats](https://github.com/openhoangnc/mac-stats)，不会跟踪本分支的风扇控制更改。请使用上面的源码构建方式保留集成功能；手动安装上游发布版本可能将其替换。

## 卸载

在源码目录运行以下任一命令：

```sh
./uninstall.sh
# 或
./install.sh --uninstall
```

脚本针对 `/Applications/MacStats.app`：停止当前用户的应用、注销登录启动项、经管理员认证移除已安装的 MacStats 辅助程序、删除应用及该用户的偏好设置。如果风扇恢复失败，卸载会停止并保留恢复文件。对于放在 `/Applications` 之外的构建，请先在面板中移除辅助程序、关闭 **Launch at Login**、退出应用，再删除对应的应用包。

## 测试与命令行

```sh
bash test.sh
```

该命令运行 31 项模拟硬件行为测试，以及 shell 语法和 plist 检查。测试覆盖配置校验、曲线插值、RPM 范围、90°C 覆盖策略、会话所有权、看门狗/断线恢复、传感器及固件错误、恢复日志，不会写入真实风扇。集成应用也已通过通用构建、签名验证、界面检查和 M4 实机只读传感器检查；这些结果不代表已验证真实辅助程序风扇控制。

| 命令或参数 | 行为 |
| --- | --- |
| `open MacStats.app --args --fan-control` | 在支持的 Mac 上启动时打开风扇控制；应用已运行时请从菜单打开 |
| `MacStats.app/Contents/Resources/MacStatsFanHelper --probe` | 输出温度和风扇状态的只读 JSON 快照 |
| 应用二进制参数 `--cleanup-login-item`、`--uninstall-login-item`、`--uninstall` | 注销登录启动项并退出，不会删除应用或辅助程序 |

## 发布

[`.github/workflows/release.yml`](.github/workflows/release.yml) 在推送 `v*` 标签、手动运行，或向 `main` 推送包含 `[deploy-prod]` 提交消息时构建并发布 `MacStats.zip`。普通推送不会发布，仅修改 Markdown 的推送被排除。工作流写入版本号、构建通用应用和辅助程序，并将压缩包附加到 GitHub Release。

## 来源与许可证

本分支基于 [MacStats](https://github.com/openhoangnc/mac-stats)，并集成本地 MacFan 实现。风扇 SMC 实现包含基于 Stats 的 MIT 许可代码；作者署名及许可证保存在 [FanControl/Resources/Stats-LICENSE.txt](FanControl/Resources/Stats-LICENSE.txt)，并随应用打包。
