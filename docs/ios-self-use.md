# Kira iOS 自用版

此工程基于 [caolib/kira](https://github.com/caolib/kira) 的 Flutter 源码补充 iOS 适配，保留上游 MIT 许可证。面向自己的 iPhone／iPad 安装使用，不包含 App Store 发布或签名证书。

可以使用免费的 Apple ID／Personal Team，将应用签名安装到自己的 iPad 或 iPhone。

## 当前验证状态

验证日期：2026-11-04。上游基线：`239d0056cb00d6df04bc97fc2b08c8c2e380143b`（1.7.5+615），本分支应用版本 **1.7.5（616）**。

- Xcode 27.2 已完成 Release 真机构建、个人开发签名及签名校验。
- 已安装到 **iPad Air 11 英寸（M3），iPadOS 26.6.2**；开发者模式及个人开发者信任已完成。
- `devicectl` 已成功启动应用，并确认进程持续运行及主界面正常显示。运行使用 Release，无需保持 Flutter 调试连接。
- `flutter analyze --no-pub`：零问题。99 项相关测试中 95 项通过；4 项失败均在干净上游基线重现。新增 4 项 iOS／离线路径回归测试全部通过；另 2 项备份目录过滤测试通过。
- 图片加载调整另通过 37 项相关测试：10 项封面组件、17 项阅读器解码／导航、10 项封面下载／缓存。覆盖超时真实取消、队列释放、旧缓存复用与条件请求；真机加载耗时仍待对比，不把测试通过视为网络提速证明。
- 616 版真机使用反馈：封面加载有所改善，漫画阅读仍慢；尚未获得可比较的逐页耗时，继续排查图片传输与预取。
- `pubspec.lock` 保持上游内容；新增 `ios/Podfile.lock` 固定原生依赖。
- 初次移植的 615 版 Apple Silicon 模拟器构建成功，产物为 `build/ios-simulator/Build/Products/Debug-iphonesimulator/Runner.app`，已核验 arm64 与 IOSSIMULATOR 平台；图片调整后的 616 版以真实 iPad 构建为准，未另外完成模拟器交互验收。
- 尚未逐项验证账号登录、在线阅读、相册写入、备份恢复等完整业务流程；本次已完成安装、启动及主界面确认。

## 环境

| 项目 | 要求 |
| --- | --- |
| Mac | 安装完整 Xcode，首次启动后完成组件安装及许可确认 |
| Flutter | **3.44.2**，以仓库根目录 `.flutter-version` 为准 |
| Dart | 使用上述 Flutter 自带版本 |
| CocoaPods | `pod` 命令可用，用于安装 iOS 原生插件 |
| 命令行真机安装 | Xcode 提供 `xcrun devicectl`；Apple 账号已登录 Xcode |
| 运行系统 | iOS／iPadOS **15.0 或更新版本** |
| 默认应用标识 | `io.github.caolib.kira`；个人签名使用自己的唯一标识 |
| 签名 | Automatic；Team 留给自己的 Apple 账号选择 |

Flutter SDK 与 Xcode SDK 是两件事：本仓库不附带 Flutter SDK，脚本也不会自动安装它。`setup` 会下载构建所需的 Flutter iOS 引擎资源、pub.dev 依赖和 CocoaPods 依赖，需要网络。

本项目固定使用 **CocoaPods** 集成原生插件。`pubspec.yaml` 的 `flutter.config.enable-swift-package-manager: false` 关闭本工程的实验性 Swift Package Manager 自动迁移；无需更改 Flutter 的全局设置。

工程将所有 Pod 的最低系统版本统一为 iOS 15，以满足 Xcode 27 的校验。构建脚本还为 Dart 原生插件提供项目内的 `xcrun` 包装入口，避免子进程过滤 `DEVELOPER_DIR` 后错误使用 Command Line Tools；不修改系统全局 Xcode 选择或依赖缓存源码。

安装 Flutter 时使用 [Flutter SDK 归档](https://docs.flutter.dev/install/archive) 中与 Mac 芯片对应的 3.44.2。CocoaPods 可按 [官方安装说明](https://guides.cocoapods.org/using/getting-started.html) 配置。不要为了本工程切换 pub.dev 镜像或重新生成 `pubspec.lock`。

## 准备工程

在终端进入项目根目录。下文所有命令均在含 `pubspec.yaml` 的目录执行。

```sh
# 如果 Flutter 尚未加入 PATH，指定实际安装目录。
export FLUTTER_ROOT="/你的实际路径/flutter"

# 可选：为本工程指定依赖缓存位置。
# export PUB_CACHE="/你的实际路径/pub-cache"

./scripts/ios.sh doctor
./scripts/ios.sh setup
```

脚本优先使用 `FLUTTER_ROOT`，其次寻找 PATH 中的 `flutter`。请根据自己的 SDK 安装位置配置路径；可通过 `PUB_CACHE` 指定依赖缓存目录。

脚本检查 Flutter 版本，使用 `flutter pub get --enforce-lockfile`，并确认锁文件没有变化。它只为当前进程选择完整 Xcode，不修改全局 `xcode-select`。如果 Xcode 装在其他位置，可以先设置：

```sh
export DEVELOPER_DIR="/实际路径/Xcode.app/Contents/Developer"
```

`flutter doctor` 可能同时报告未安装 Android 工具链；纯 iOS 开发重点检查 Xcode、CocoaPods 及 iOS 设备项。

## 在模拟器里运行

只构建模拟器 App：

```sh
./scripts/ios.sh simulator
```

产物位于 `build/ios-simulator/Build/Products/Debug-iphonesimulator/Runner.app`，只能用于模拟器。它不能安装到真实 iPad 或 iPhone。

要启动并连接 Flutter 调试，先从 `doctor` 输出复制可用模拟器 UDID：

```sh
./scripts/ios.sh simulator "替换成模拟器UDID"
```

终端保持连接时可使用 Flutter 的热重载操作。脚本兼容旧版 `Simulator.app` 和 Xcode 27.2 的 `DeviceHub.app` 界面。没有可用模拟器时，在 Xcode 的 Settings → Components（部分版本为 Platforms）安装 iOS Simulator runtime，再到设备与模拟器管理界面创建模拟器。

## 用免费 Apple ID 安装到自己的 iPad

1. 保持 iPad 与 Mac 的数据线连接，解锁 iPad，接受“信任此电脑”。
2. 在 Xcode → Settings → Accounts 添加自己的 Apple 账号。
3. 运行 `./scripts/ios.sh open`，打开 **`ios/Runner.xcworkspace`**。不要只打开 `Runner.xcodeproj`，否则 CocoaPods 插件可能无法链接。
4. 在左侧选择 Runner 工程，再选择 **TARGETS → Runner → Signing & Capabilities**。保留 **Automatically manage signing**，在 **Team** 选择自己的 **Personal Team**。
5. 默认 Bundle Identifier 为 `io.github.caolib.kira`。个人签名请在 `ios/Flutter/Local.xcconfig` 中设置自己的唯一 `KIRA_BUNDLE_IDENTIFIER`，例如 `com.yourname.kira`，并确认 Xcode 显示对应标识。下节提供完整配置示例。后续升级安装应继续使用同一标识和 Team，以保留应用数据。
6. 在 Xcode 顶部运行目标选择这台真实 **iPad**，不要选 iPad 模拟器或通用 iOS 设备。iPadOS 16 或更新版本如提示需要开发者模式，在 iPad 的 **设置 → 隐私与安全性 → 开发者模式** 开启，并按提示重启确认。
7. 选择 Product → Run（⌘R），等待 Xcode 完成签名并安装。如果 iPad 提示开发者不受信任，到 **设置 → 通用 → VPN 与设备管理**，按当前系统提示信任自己的开发者身份。

免费 Personal Team 的开发签名通常约 **7 天**有效，到期后重新连接 Mac 并用同一 Team、同一 Bundle Identifier 运行安装即可。具体额度及有效期以 Xcode／Apple 账号的当前提示为准，不需要为了首次自用安装先购买付费开发者会员。

首次建议用 Xcode Run 排查。需要日常直接从 iPad 主屏幕启动时，可在 Product → Scheme → Edit Scheme → Run → Info 将 **Build Configuration** 设为 **Release** 后再次运行安装；Flutter Debug 构建适合保持调试连接，不应作为最终独立运行验证的依据。安装后应断开调试连接，再从 iPad 主屏幕启动一次验证。

未来安装到自己的 iPhone 时可沿用以上步骤，只需选择对应真机；开发者模式要求以设备系统提示为准。

已有付费开发者账号时，在 Team 选择对应团队即可。本工程未配置 TestFlight 或分发描述文件。

## 使用脚本签名、安装到指定设备

首次完成 Xcode 账号登录、开发者模式和信任后，可以复用安装脚本。在 `ios/Flutter/Local.xcconfig` 中保存自己的 Team 和唯一应用标识；Debug／Profile／Release 都会读取它，此文件已被 Git 忽略，不应提交到公共仓库。创建文件时将下面两个示例值替换为自己的配置；已有安装使用原来的 Team 和 Bundle Identifier：

```xcconfig
DEVELOPMENT_TEAM = 你的10位TeamID
KIRA_BUNDLE_IDENTIFIER = com.yourname.kira
```

连接并解锁设备，将 `<设备UDID>` 替换为实际标识，在项目根目录执行：

```sh
./scripts/ios.sh install "<设备UDID>"
```

`install` 必须显式指定真机 UDID，不会自动选择连接的其他设备。换设备时可在 Xcode 设备管理界面查到该设备的 Identifier。脚本会检查锁定依赖、刷新 Flutter Release 配置，再由 Xcode 使用 `Local.xcconfig` 的 Team 自动签名；允许 Xcode 更新描述文件并登记所指定设备。账号未登录、签名配额不足或证书不可用时，会保留 Xcode 的实际错误并停止。

签名产物位于 `build/ios-signed/Build/Products/Release-iphoneos/Runner.app`。安装前会检查签名、设备描述文件及 Team 是否匹配，随后用 `devicectl` 安装并发出启动请求。安装与启动记录写入 `build/ios-signed/install-result.json` 和 `launch-result.json`。脚本不会把 `device` 命令生成的未签名产物直接安装。

如安装成功但启动失败，先在 iPad 上检查解锁状态、开发者模式及信任提示。日常运行仍需在 iPad 主屏幕手动启动一次确认。免费签名到期后可重复同一安装命令；保持原 Bundle Identifier 和 Team。

## 无签名构建与已安装 App 的区别

```sh
./scripts/ios.sh device
```

此命令执行 `flutter build ios --release --no-codesign --no-pub`，生成 `build/ios/iphoneos/Runner.app`。它用于检查真机架构的 Release 编译是否通过，**没有完成签名，不能直接装到 iPad／iPhone，也不是可安装的 IPA**。产物目录名 `iphoneos` 同时适用于 iPad 真机，不代表仅支持 iPhone。

真正安装需要 Xcode 使用你的 Team、开发证书和设备描述文件完成签名。工程不包含证书、私钥或开发者账号；不要把这些内容放进源码包或提交到 Git。

## iOS 功能差异

- 漫画与轻小说沿用上游界面和数据接口。服务是否可访问，仍取决于第三方服务及设备网络；首次联网、账号登录和在线阅读需要单独验证。
- iOS 下载保存在应用沙盒内。可在系统“文件”App 的“我的 iPhone／iPad → Kira”查看暴露的 Documents 内容。不要手动移动或删除正在使用的下载清单和文件。
- 下载应保持应用在前台。切换到其他 App 或锁屏后，iOS 可能挂起进程；本版本不承诺持续后台下载。返回应用后检查任务状态。
- 保存漫画图片使用系统相册的“仅添加照片”权限。仅在主动保存时按提示授权。
- Android 专属的音量键翻页、显示模式和前台服务能力不作为 iOS 功能提供；iOS 保留触摸阅读操作。
- 支持 `kira://` 自定义链接。没有配置第三方域名的 Apple Universal Links 关联，https 分享页是否自动拉起应用由浏览器和落地页决定。
- 备份、日志导出通过系统文件选择器完成。局域网 WebDAV／代理仅在用户自己配置并允许网络访问后可用，HTTPS 优先。
- 拷贝默认网页登录路线不需要 `COPY_AUTH_KEY`。上游的 App 登录通道当前本来就关闭；本次移植未获取或嵌入作者 CI 中的密钥，也不以该通道作为使用前提。

## 建议验收

### 图片加载调整

- 封面按显示宽度与屏幕像素密度缩放解码；阅读器的预取、显示和宽高比读取共用相同解码缓存，避免额外解码原尺寸图片。磁盘保留原图，图片查看器仍可读取原图。
- 封面与头像沿用原缓存目录及数据库。下载设置 15 秒连接／响应空闲超时和 30 秒总期限，超时取消对应网络请求并释放下载名额；缓存管理页仍清理同一份缓存。
- 这些调整减少内存开销和慢请求占位，不减少原图下载流量，也不能保证第三方图片服务器的首次传输速度。应在实际设备上比较同一页面的首次加载、再次打开和连续翻页。

安装后先检查首页、搜索、漫画／小说阅读、切换主题与应用图标；再检查图片保存、下载后重启继续阅读、备份导出／恢复。iPad 还应检查分享面板与横屏布局。

遇到问题时保留真实报错及系统版本。构建问题优先记录终端输出；应用内问题可从日志页面导出。未验证的功能应继续标记为未验证，不用“构建成功”代替实际操作结果。
