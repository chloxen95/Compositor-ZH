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

# 从 pbxproj 读构建设置。两个容易踩的点：
#   · 字段前缀是制表符，不是空格——模式里必须用 [[:space:]]。
#   · set -e 下，一次没有匹配的赋值会在后面打印诊断之前就静默退出（退出码 1、
#     无输出）。所以这里吞掉失败，由下面的显式校验负责报错。
setting() { grep -m1 "^[[:space:]]*$1 = " "$PBX" 2>/dev/null | sed -E 's/.*= ([^;]+);.*/\1/' || true }
VERSION=$(setting MARKETING_VERSION)
BUILD=$(setting CURRENT_PROJECT_VERSION)
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+ ]] || { print -u2 -- "❌ 读不出 MARKETING_VERSION（$VERSION）"; exit 1; }
[[ "$BUILD" =~ ^[0-9]+$ ]] || { print -u2 -- "❌ 读不出 CURRENT_PROJECT_VERSION（$BUILD）"; exit 1; }
INJECTED=$(( BUILD * 10 + ZH_REV ))

print -r -- "▸ 上游基线 $VERSION ($BUILD) → 汉化版 build $INJECTED"

# 先清构建产物，但**不要** `rm -rf` 整个派生数据目录：
#   · 连带删掉 SourcePackages 后，每次构建都要重新联网 clone Sparkle，构建变成网络依赖；
#   · 一次删两千多个文件，在受限环境里会触发文件安全策略、直接拦下整条命令。
# 用 xcodebuild clean 描述意图（清产物），把「删哪些文件」交给构建系统。
xcodebuild clean -quiet \
    -project "$PROJECT_DIR/$APP.xcodeproj" -scheme "$APP" -configuration Release \
    -derivedDataPath "$WORK" >/dev/null 2>&1 || true

# ── 两项环境适配，全部走命令行注入，不碰 project.pbxproj ──────────────────
#
# ① 沙箱。Xcode 会用 sandbox-exec 跑两件事：解析 SPM 包清单、启动宏插件服务。
#    在容器或受限会话里，内核直接拒绝 sandbox_apply，于是构建在编译任何一行
#    代码之前就失败，报错是 "sandbox-exec: sandbox_apply: Operation not permitted"
#    或 "swift-plugin-server produced malformed response"——后者尤其误导，看着像
#    宏坏了，其实是沙箱起不来。检测到这种环境才关，正常机器上不动安全边界。
#
# ② 签名。上游工程写死了他自己的 "Mac Development" 证书与 team id，我们没有。
#    本地自用改用 ad-hoc（"-"）。不能用 CODE_SIGNING_ALLOWED=NO：arm64 上未签名
#    的二进制根本起不来。要分发时传 ZH_SIGN_IDENTITY="Developer ID Application: …"。
BUILD_ARGS=()
if ! sandbox-exec -p '(version 1)(allow default)' /usr/bin/true 2>/dev/null; then
    print -r -- "▸ 本机 sandbox-exec 不可用 → 关闭包清单与宏插件沙箱（仅影响本机构建）"
    defaults write com.apple.dt.Xcode IDEPackageSupportDisableManifestSandbox -bool YES
    BUILD_ARGS+=(OTHER_SWIFT_FLAGS="-disable-sandbox")
fi

SIGN_IDENTITY="${ZH_SIGN_IDENTITY:--}"
(( ${#SIGN_IDENTITY} )) || SIGN_IDENTITY="-"
BUILD_ARGS+=(CODE_SIGN_IDENTITY="$SIGN_IDENTITY" CODE_SIGN_STYLE=Manual)
if [[ "$SIGN_IDENTITY" == "-" ]]; then
    # 加固运行时会打开「库校验」：主可执行文件只允许加载同一 team 签名的库。
    # ad-hoc 签名没有 team，于是内嵌的 Sparkle.framework（Sparkle 官方签名）
    # 会被 dyld 拒绝，报 "mapping process and mapped file have different Team IDs"，
    # App 一启动就崩。本地自用必须同时关掉它；真用 Developer ID 签名分发时，
    # 整包同一个 team，库校验自然通过，不要传这个开关。
    BUILD_ARGS+=(ENABLE_HARDENED_RUNTIME=NO)
    print -r -- "▸ 签名：ad-hoc + 关闭加固运行时（本机可用，不可分发）"
fi

xcodebuild build -quiet \
    -project "$PROJECT_DIR/$APP.xcodeproj" -scheme "$APP" -configuration Release \
    -destination 'platform=macOS' -derivedDataPath "$WORK" \
    MARKETING_VERSION="$VERSION" CURRENT_PROJECT_VERSION="$INJECTED" \
    "${BUILD_ARGS[@]}"

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
