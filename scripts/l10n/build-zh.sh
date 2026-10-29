#!/bin/zsh
# 构建简体中文版，并给它一个不会与上游撞车的 build 号。
#
# 为什么要注入版本号：Sparkle 只比较 CFBundleVersion（build 号）。若我们和上游都用 58，
# 那么「我们的 58」和「上游的 58」无法区分，自己的更新链也就无法成立。
#
# 方案：build = 上游 build × 10 + 汉化修订号。
#   上游 58 的第 1 个汉化版 → 581；同基础再发一版 → 582；上游升到 59 → 591。
# 全程单调递增，且能一眼看出基于哪个上游版本。
#
# 版本号只从命令行注入，**不写进 project.pbxproj**：上游每次发版都会改那里的
# MARKETING_VERSION 与 CURRENT_PROJECT_VERSION，我们若也改同一行，合并必冲突。
#
# 用法：
#   scripts/l10n/build-zh.sh              # Release 构建
#   ZH_REV=2 scripts/l10n/build-zh.sh     # 同一上游基线上再发一版
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
APP=Compositor
PBX="$PROJECT_DIR/$APP.xcodeproj/project.pbxproj"
WORK="$HOME/Library/Caches/CompositorZH"
ZH_REV="${ZH_REV:-1}"

xcode-select -p 2>/dev/null | grep -q "Xcode.app" \
    || { print -u2 -- "❌ 需要完整 Xcode（xcodebuild）。装好后：sudo xcode-select -s /Applications/Xcode.app"; exit 3; }

setting() { grep -m1 " $1 = " "$PBX" | sed -E 's/.*= ([^;]+);.*/\1/' }
VERSION=$(setting MARKETING_VERSION)
BUILD=$(setting CURRENT_PROJECT_VERSION)
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+ ]] || { print -u2 -- "❌ 读不出 MARKETING_VERSION（$VERSION）"; exit 1; }
[[ "$BUILD" =~ ^[0-9]+$ ]] || { print -u2 -- "❌ 读不出 CURRENT_PROJECT_VERSION（$BUILD）"; exit 1; }
INJECTED=$(( BUILD * 10 + ZH_REV ))

print -r -- "▸ 上游基线 $VERSION ($BUILD) → 汉化版 build $INJECTED"
rm -rf "$WORK"

xcodebuild build -quiet \
    -project "$PROJECT_DIR/$APP.xcodeproj" -scheme "$APP" -configuration Release \
    -destination 'platform=macOS' -derivedDataPath "$WORK" \
    MARKETING_VERSION="$VERSION" CURRENT_PROJECT_VERSION="$INJECTED"

APP_PATH="$WORK/Build/Products/Release/$APP.app"
PLIST="$APP_PATH/Contents/Info.plist"
[[ -d "$APP_PATH" ]] || { print -u2 -- "❌ 构建产物不存在：$APP_PATH"; exit 1; }

# 自检：确认注入真的落到了 Info.plist，而不是被生成规则忽略。
ACTUAL_BUILD=$(plutil -extract CFBundleVersion raw "$PLIST")
ACTUAL_VERSION=$(plutil -extract CFBundleShortVersionString raw "$PLIST")
ACTUAL_FEED=$(plutil -extract SUFeedURL raw "$PLIST")
if [[ "$ACTUAL_BUILD" != "$INJECTED" ]]; then
    print -u2 -- "❌ 版本注入未生效：Info.plist 里是 $ACTUAL_BUILD，期望 $INJECTED"
    exit 1
fi

print -r -- "✅ 构建完成"
print -r -- "   路径： $APP_PATH"
print -r -- "   版本： $ACTUAL_VERSION ($ACTUAL_BUILD)"
print -r -- "   更新源：$ACTUAL_FEED"
print -r --
print -r -- "本机自用：open \"$APP_PATH\""
print -r -- "要分发给别人：需 Developer ID 证书与公证，见 l10n/RELEASE.md"
