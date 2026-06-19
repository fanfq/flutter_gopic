#!/bin/sh
set -e

SHELL_FOLDER=$(cd "$(dirname "$0")"; pwd)
DIST_FOLDER=$SHELL_FOLDER/dist/
if [ ! -d "$DIST_FOLDER" ]; then
  mkdir -p "$DIST_FOLDER"
fi
echo "$DIST_FOLDER"


# ----- Flutter 版本配置（按需修改此处即可）-----
FLUTTER_BIN=flutter
# FLUTTER_BIN=/Users/fred/apps/flutter-3.38.9/bin/flutter
# FLUTTER_BIN=/Users/fred/apps/flutter-3.35.2/bin/flutter
# -------------------------------------------

echo "build macos desktop app "
echo "$FLUTTER_BIN build macos"

#编译
$FLUTTER_BIN build macos

#清空老文件
rm -rf "$DIST_FOLDER"/*.app

# 只复制最新的包
LATEST_RELEASE=$(ls -td build/macos/Build/Products/Release/*.app | head -1)
cp -R "$LATEST_RELEASE" "$DIST_FOLDER"


echo "\n"
# 输出当前 Flutter 版本
echo "======================================"
echo "Flutter path: $FLUTTER_BIN"
echo "Flutter version:"
$FLUTTER_BIN --version | head -3
echo "======================================\n"
# 输出产出物路径
echo "======================================"
echo "Build output copied to: ${DIST_FOLDER}$(basename "$LATEST_RELEASE")"
echo "======================================"
