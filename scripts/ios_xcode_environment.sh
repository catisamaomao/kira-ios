#!/bin/bash

# Dart native-asset hooks preserve PATH but strip DEVELOPER_DIR. Give each
# selected Xcode a project-local xcrun shim so hooks use the same SDK as Runner.
kira_prepare_xcode_tools() {
  local project_root="$1"
  local selected toolchain_key shim_directory temporary_shim

  selected="${DEVELOPER_DIR:-}"
  if [[ -z "$selected" ]]; then
    selected="$(/usr/bin/xcode-select -p 2>/dev/null || true)"
    if [[ ! -x "$selected/usr/bin/xcodebuild" ]]; then
      selected=/Applications/Xcode.app/Contents/Developer
    fi
  fi
  if [[ -d "$selected/Contents/Developer" ]]; then
    selected="$selected/Contents/Developer"
  fi
  if [[ ! -x "$selected/usr/bin/xcodebuild" ]]; then
    printf '错误：未找到完整 Xcode，请设置 DEVELOPER_DIR；当前路径：%s\n' "$selected" >&2
    return 1
  fi
  export DEVELOPER_DIR="$(cd "$selected" && pwd -P)"

  toolchain_key="$(printf '%s' "$DEVELOPER_DIR" | /usr/bin/shasum -a 256 | /usr/bin/awk '{print $1}')"
  shim_directory="$project_root/ios/Flutter/ephemeral/kira-toolchains/$toolchain_key"
  /bin/mkdir -p "$shim_directory"
  temporary_shim="$(/usr/bin/mktemp "$shim_directory/.xcrun.XXXXXX")"
  {
    printf '#!/bin/bash\n'
    # %q encodes spaces, quotes and shell metacharacters as one literal value.
    printf 'export DEVELOPER_DIR=%q\n' "$DEVELOPER_DIR"
    printf 'exec /usr/bin/xcrun "$@"\n'
  } > "$temporary_shim"
  /bin/chmod 755 "$temporary_shim"
  /bin/mv -f "$temporary_shim" "$shim_directory/xcrun"
  export PATH="$shim_directory:$PATH"
}
