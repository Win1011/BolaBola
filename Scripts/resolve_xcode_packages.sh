#!/usr/bin/env bash
# 在 Xcode 报 Missing package product（如 FirebaseAnalytics）或清空 DerivedData 后执行，重新解析 Swift Package。
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
XCB="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}/usr/bin/xcodebuild"
if [[ ! -x "$XCB" ]]; then
  echo "找不到 xcodebuild：请安装 Xcode 并执行: sudo xcode-select -s /Applications/Xcode.app/Contents/Developer" >&2
  exit 1
fi
exec "$XCB" -resolvePackageDependencies -project "$ROOT/BolaBola.xcodeproj" -scheme BolaBola "$@"
