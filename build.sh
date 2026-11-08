#!/usr/bin/env bash
# 在 WSL / Linux 里执行：校验清单 + 用 xtool 构建 iOS App
set -euo pipefail

cd "$(dirname "$0")"

# 本机 WSL 环境（由 2026-11-07 的安装步骤生成）；别的机器上没有就跳过
if [ -f "$HOME/.swift_env" ]; then
  # shellcheck disable=SC1091
  source "$HOME/.swift_env"
fi
# Ubuntu 25.04 + Swift 24.04 工具链需要补的 sysroot
if [ -d "$HOME/sysroot" ]; then
  export SDKROOT="$HOME/sysroot"
fi

# xtool CLI 位置：优先本机已下载的 AppImage，其次 PATH 里的 xtool
if [ -x "$HOME/bin/xtool-full" ]; then
  XTOOL="$HOME/bin/xtool-full"
else
  XTOOL="$(command -v xtool)"
fi

echo "== 工具链 =="
swift --version 2>&1 | head -2
"$XTOOL" --version

echo
echo "== Darwin SDK 状态 =="
if "$XTOOL" sdk status 2>&1 | grep -qi "not installed"; then
  echo "未安装 Darwin SDK。先执行（离线，无需 Apple 登录）："
  echo "  $XTOOL sdk install /path/to/Xcode_27.xip"
  echo "  swift sdk list   # 应看到 darwin"
  echo "然后再运行本脚本。"
  exit 1
fi

echo
echo "== 清单校验 =="
swift package describe > /dev/null
echo "Package.swift OK"

echo
echo "== 构建 .app（不签名、不需要手机）=="
"$XTOOL" dev build "$@"

echo
echo "提示：签名并装到真机用  $XTOOL dev  （需要 Apple ID 登录 + USB 连接的 iPhone）"
