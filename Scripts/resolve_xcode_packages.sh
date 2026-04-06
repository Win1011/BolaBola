#!/usr/bin/env bash
# 重新解析 Swift Package（FirebaseCore、Lottie 等）。
# 适用：Xcode 报 Missing package product、清空 DerivedData/Caches 或换机后。
# 前提：已安装 Xcode.app，且本机能访问 GitHub（必要时开代理/VPN）。
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
XCB="$DEVELOPER_DIR/usr/bin/xcodebuild"

if [[ ! -x "$XCB" ]]; then
  echo "找不到 xcodebuild（路径: $XCB）。" >&2
  echo "请安装 Xcode，并执行: sudo xcode-select -s /Applications/Xcode.app/Contents/Developer" >&2
  exit 1
fi

if [[ "$(xcode-select -p 2>/dev/null)" != "$DEVELOPER_DIR" ]]; then
  echo "提示: 当前 xcode-select 未指向 Xcode.app。若命令行解析失败，请执行:" >&2
  echo "  sudo xcode-select -s $DEVELOPER_DIR" >&2
fi

echo "使用 DEVELOPER_DIR=$DEVELOPER_DIR"
echo "正在解析 Swift Package 依赖（需访问 github.com）..."
"$XCB" -resolvePackageDependencies -project "$ROOT/BolaBola.xcodeproj" -scheme BolaBola "$@"
echo "解析完成。请在 Xcode 中执行 Product → Clean Build Folder 后重新编译。"
