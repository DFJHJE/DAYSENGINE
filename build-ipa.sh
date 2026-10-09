#!/bin/bash
# Builds an unsigned .ipa from this project. Runs on macOS only (Linux/Windows cannot link an
# iOS binary), which is why CI uses a macOS runner.
#
#   ./build-ipa.sh            -> dist/DaysEngine-unsigned.ipa
#
# The result is UNSIGNED: iOS will refuse to install it directly. Sign it for your own device
# with Sideloadly / AltStore using your Apple ID, which is the step that cannot be automated
# away — installing anything on iOS requires an Apple-signed identity.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
cd "$here"

SCHEME="DaysEngine"
CONFIGURATION="Release"
DIST="$here/dist"
BUILD="$here/build"

echo "== 1/5 同步网页资源 =="
if [ ! -f "$here/www/index.html" ]; then
  echo "错误: 缺少 www/index.html — 先在 Windows 上运行 web/build-web.ps1，再把产物复制过来。" >&2
  exit 1
fi
echo "   www/index.html  $(wc -c < "$here/www/index.html") bytes"

echo "== 2/5 生成 Xcode 工程 =="
if ! command -v xcodegen >/dev/null 2>&1; then
  echo "找不到 xcodegen。安装: brew install xcodegen" >&2
  exit 1
fi
xcodegen generate --spec project.yml --project .

echo "== 3/5 编译（禁用签名）=="
xcodebuild \
  -project DaysEngine.xcodeproj \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -sdk iphoneos \
  -derivedDataPath "$BUILD" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  CODE_SIGN_ENTITLEMENTS="" \
  ONLY_ACTIVE_ARCH=NO \
  clean build

app="$BUILD/Build/Products/$CONFIGURATION-iphoneos/$SCHEME.app"
if [ ! -d "$app" ]; then
  echo "错误: 没有找到构建产物 $app" >&2
  exit 1
fi

echo "== 4/5 校验产物 =="
if [ ! -f "$app/$SCHEME" ]; then
  echo "错误: .app 里没有可执行文件 $SCHEME" >&2
  exit 1
fi
if [ ! -f "$app/www/index.html" ]; then
  echo "错误: .app 里没有打包进 www/index.html" >&2
  exit 1
fi
echo "   可执行文件  $(wc -c < "$app/$SCHEME") bytes"
echo "   网页资源    $(wc -c < "$app/www/index.html") bytes"
echo "   图标:       $(ls "$app" | grep -c 'AppIcon' || true) 个文件"

echo "== 5/5 打包 ipa =="
# The launcher reads .GPK files from Documents, so the bundle ships that folder pre-made for the
# user to drop files into via the Files app or Finder file sharing. It has to be created before
# the .app is copied into Payload, or the copy carries an empty directory.
mkdir -p "$app/Documents"
cat > "$app/Documents/README.txt" <<'TXT'
把游戏归档与密钥放进这个目录：
  BGM.GPK              背景音乐（启动器的主题曲）
  SysSe.GPK            界面音效
  Voice0x.GPK, GenSe.GPK   语音与通用音效（可选）
  daysengine-key.json  由 DaysLauncher.exe --gpkkey 生成

请不要放 Movie0x.GPK：单支 1.7-2.7 GB，iOS 会因内存回收把 App 杀掉。

也可以通过「文件」App -> 我的 iPhone/iPad -> DaysEngine 放入这些文件。
TXT

rm -rf "$DIST"
mkdir -p "$DIST/Payload"
cp -R "$app" "$DIST/Payload/"

( cd "$DIST" && zip -qry "DaysEngine-unsigned.ipa" Payload && rm -rf Payload )

echo
echo "完成: $DIST/DaysEngine-unsigned.ipa ($(wc -c < "$DIST/DaysEngine-unsigned.ipa") bytes)"
echo "这是未签名包，用 Sideloadly / AltStore 配你的 Apple ID 安装。"
