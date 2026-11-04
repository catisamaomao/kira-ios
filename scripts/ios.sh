#!/bin/bash
set -euo pipefail

KIRA_ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
KIRA_FLUTTER=""
source "$KIRA_ROOT/scripts/ios_xcode_environment.sh"

usage() {
  cat <<'USAGE'
用法：./scripts/ios.sh <命令> [设备 UDID]

  doctor       检查 Flutter 版本、Xcode、CocoaPods 和可用模拟器
  setup        获取锁定依赖、iOS 引擎资源并安装 CocoaPods
  simulator    构建 Debug 模拟器 App；传入 UDID 时启动并连接调试
  device       构建 Release 真机 App（未签名，不能直接安装）
  install UDID 用 Local.xcconfig 的 Team 签名 Release，安装并启动指定真机
  open         打开已准备好的 ios/Runner.xcworkspace

可设置 FLUTTER_ROOT、DEVELOPER_DIR、PUB_CACHE；不会下载 Flutter SDK，
也不会修改全局 xcode-select。Flutter 版本必须与 .flutter-version 一致。
USAGE
}

fail() {
  printf '错误：%s\n' "$*" >&2
  exit 1
}

prepare_environment() {
  [[ "$(uname -s)" == Darwin ]] || fail 'iOS 构建需要 macOS。'
  if [[ -n "${PUB_HOSTED_URL:-}" && "${PUB_HOSTED_URL%/}" != https://pub.dev ]]; then
    fail '本工程锁定 pub.dev 依赖源，请取消自定义 PUB_HOSTED_URL 后重试。'
  fi
  if [[ -n "${FLUTTER_ROOT:-}" ]]; then
    KIRA_FLUTTER="$FLUTTER_ROOT/bin/flutter"
    [[ -x "$KIRA_FLUTTER" ]] || fail 'FLUTTER_ROOT 下没有可执行的 bin/flutter。'
  elif command -v flutter >/dev/null 2>&1; then
    KIRA_FLUTTER="$(command -v flutter)"
  elif [[ -x "$KIRA_ROOT/../../work/flutter/bin/flutter" ]]; then
    # 当前工作区的便利路径；复制项目到其他 Mac 后请设置 FLUTTER_ROOT。
    KIRA_FLUTTER="$KIRA_ROOT/../../work/flutter/bin/flutter"
    if [[ -z "${PUB_CACHE:-}" ]]; then
      export PUB_CACHE="$KIRA_ROOT/../../work/pub-cache"
    fi
  else
    fail '未找到 Flutter。请安装 .flutter-version 指定的版本，再设置 FLUTTER_ROOT 或 PATH。'
  fi

  local expected actual version_output
  expected="$(tr -d '[:space:]' < "$KIRA_ROOT/.flutter-version")"
  version_output="$("$KIRA_FLUTTER" --version)"
  actual="$(printf '%s\n' "$version_output" | awk '$1 == "Flutter" {print $2; exit}')"
  [[ "$actual" == "$expected" ]] || fail "Flutter 版本应为 $expected，当前为 ${actual:-无法识别}。"

  kira_prepare_xcode_tools "$KIRA_ROOT"
  xcodebuild -version
  command -v pod >/dev/null 2>&1 || fail '未找到 CocoaPods。请安装 CocoaPods，并将 pod 加入 PATH。'
  export COCOAPODS_DISABLE_STATS=true
  cd "$KIRA_ROOT"
  printf 'Flutter %s\n项目：%s\n' "$actual" "$KIRA_ROOT"
}

setup_project() {
  local lock_before lock_after
  lock_before="$(shasum -a 256 pubspec.lock)"
  "$KIRA_FLUTTER" precache --ios
  "$KIRA_FLUTTER" pub get --enforce-lockfile
  lock_after="$(shasum -a 256 pubspec.lock)"
  [[ "$lock_before" == "$lock_after" ]] || fail 'pubspec.lock 发生变化，请检查依赖；已停止构建。'
  if [[ -e .git ]]; then
    git diff --exit-code -- pubspec.lock
  fi
  pod install --project-directory=ios
}

open_simulator_ui() {
  local simulator_app
  # Xcode 27.2 使用 Contents/Applications/DeviceHub.app；兼容旧版布局。
  for simulator_app in \
    "$DEVELOPER_DIR/Applications/Simulator.app" \
    "$DEVELOPER_DIR/../Applications/DeviceHub.app" \
    "$DEVELOPER_DIR/Applications/DeviceHub.app" \
    "$DEVELOPER_DIR/../Applications/Simulator.app"; do
    if [[ -d "$simulator_app" ]] && open -a "$simulator_app"; then
      return 0
    fi
  done
  printf '未找到可打开的模拟器界面；设备已启动，继续连接 Flutter 调试。\n' >&2
}

install_on_device() {
  local device_udid="$1"
  local local_config="$KIRA_ROOT/ios/Flutter/Local.xcconfig"
  local team_id signed_team signed_app bundle_id
  local signed_build="$KIRA_ROOT/build/ios-signed"
  [[ -f "$local_config" ]] || fail '缺少 ios/Flutter/Local.xcconfig；请先配置自己的 DEVELOPMENT_TEAM。'
  # 此文件不执行为 shell；只读取显式 Team ID，避免把签名配置当作代码。
  team_id="$(awk '
    /^[[:space:]]*DEVELOPMENT_TEAM[[:space:]]*=/ {
      sub(/^[^=]*=[[:space:]]*/, "")
      sub(/\/\/.*$/, "")
      gsub(/[[:space:]";]/, "")
      team = $0
    }
    END {print team}
  ' "$local_config")"
  [[ "$team_id" =~ ^[A-Z0-9]{10}$ ]] ||
    fail '请在 ios/Flutter/Local.xcconfig 中设置 DEVELOPMENT_TEAM = 你的10位TeamID。'
  xcrun --find devicectl >/dev/null

  setup_project
  # 只刷新 Flutter Release 配置；真正构建和签名由下方 Xcode 完成。
  "$KIRA_FLUTTER" build ios --release --config-only --no-codesign --no-pub
  xcodebuild \
    -workspace ios/Runner.xcworkspace \
    -scheme Runner \
    -configuration Release \
    -sdk iphoneos \
    -destination "id=$device_udid" \
    -derivedDataPath "$signed_build" \
    -allowProvisioningUpdates \
    -allowProvisioningDeviceRegistration \
    CODE_SIGN_STYLE=Automatic \
    build

  signed_app="$signed_build/Build/Products/Release-iphoneos/Runner.app"
  [[ -d "$signed_app" ]] || fail 'Xcode 未生成预期的已签名 Runner.app。'
  [[ -f "$signed_app/embedded.mobileprovision" ]] ||
    fail '产物缺少设备描述文件，停止安装。'
  codesign --verify --deep --strict "$signed_app"
  signed_team="$(codesign -d --verbose=4 "$signed_app" 2>&1 | sed -n 's/^TeamIdentifier=//p')"
  [[ "$signed_team" == "$team_id" ]] ||
    fail '产物签名 Team 与 Local.xcconfig 不一致，停止安装。'
  bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$signed_app/Info.plist")"
  [[ -n "$bundle_id" ]] || fail '无法读取已签名应用的 Bundle Identifier。'

  xcrun devicectl device install app \
    --device "$device_udid" \
    --json-output "$signed_build/install-result.json" \
    "$signed_app"
  if ! xcrun devicectl device process launch \
    --device "$device_udid" \
    --json-output "$signed_build/launch-result.json" \
    "$bundle_id"; then
    fail 'App 已安装，但启动未成功。请解锁设备，检查开发者模式和开发者信任，然后从设备主屏幕重试。'
  fi
  printf '已签名安装，并已提交启动请求：%s\n设备：%s\n' "$bundle_id" "$device_udid"
  printf '请在设备上确认界面；此命令的成功不代表在线服务和全部功能已验证。\n'
}

command_name="${1:-help}"
case "$command_name" in
  help|-h|--help)
    usage
    exit 0
    ;;
  doctor|setup|simulator|device|install|open) ;;
  *) usage >&2; fail "未知命令：$command_name" ;;
esac
if [[ "$command_name" == simulator ]]; then
  [[ $# -le 2 ]] || fail 'simulator 最多接受一个模拟器 UDID。'
elif [[ "$command_name" == install ]]; then
  [[ $# -eq 2 ]] || fail 'install 必须显式提供真机 UDID，例如 ./scripts/ios.sh install "<设备UDID>"。'
  [[ "$2" =~ ^([[:xdigit:]]{8}-[[:xdigit:]]{16}|[[:xdigit:]]{40})$ ]] ||
    fail 'install 参数必须是完整真机 UDID，不能使用设备名称或模拟器 UUID。'
else
  [[ $# -eq 1 ]] || fail '此命令不接受附加参数。'
fi

prepare_environment
case "$command_name" in
  doctor)
    pod --version
    "$KIRA_FLUTTER" doctor -v
    xcrun simctl list devices available
    ;;
  setup)
    setup_project
    ;;
  simulator)
    setup_project
    if [[ -n "${2:-}" ]]; then
      xcrun simctl bootstatus "$2" -b
      open_simulator_ui
      "$KIRA_FLUTTER" run --no-pub --debug -d "$2"
    else
      # Xcode 27.2's lipo rejects Flutter's multi-architecture -verify_arch
      # invocation. A local simulator only needs this Mac's native architecture.
      KIRA_SIMULATOR_ARCH="$(uname -m)"
      case "$KIRA_SIMULATOR_ARCH" in
        arm64|x86_64) ;;
        *) fail "不支持的模拟器宿主架构：$KIRA_SIMULATOR_ARCH" ;;
      esac
      "$KIRA_FLUTTER" build ios --simulator --debug --config-only --no-pub
      xcodebuild \
        -workspace ios/Runner.xcworkspace \
        -scheme Runner \
        -configuration Debug \
        -sdk iphonesimulator \
        -destination 'generic/platform=iOS Simulator' \
        -derivedDataPath "$KIRA_ROOT/build/ios-simulator" \
        "ARCHS=$KIRA_SIMULATOR_ARCH" \
        ONLY_ACTIVE_ARCH=YES \
        CODE_SIGNING_ALLOWED=NO \
        CODE_SIGNING_REQUIRED=NO \
        build
      printf '模拟器构建完成：%s/build/ios-simulator/Build/Products/Debug-iphonesimulator/Runner.app\n' "$KIRA_ROOT"
    fi
    ;;
  device)
    setup_project
    "$KIRA_FLUTTER" build ios --release --no-codesign --no-pub
    printf '未签名真机构建：%s/build/ios/iphoneos/Runner.app\n' "$KIRA_ROOT"
    printf '该文件不能直接安装。请在 Xcode 中选择自己的 Team 和 iPad／iPhone 后签名运行。\n'
    ;;
  install)
    install_on_device "$2"
    ;;
  open)
    [[ -f ios/Flutter/Generated.xcconfig && -f ios/Pods/Manifest.lock ]] ||
      fail '请先运行 ./scripts/ios.sh setup，生成 Flutter 与 CocoaPods 配置。'
    open ios/Runner.xcworkspace
    ;;
esac
