#!/bin/bash
# 源码静态校验的两个层次，按本机工具链自动选择。
#
#   1. 语法层（默认，只需要 Command Line Tools）
#      swiftc -parse 解析全部 App 源码。能抓括号、拼写、语句结构错误；不解析 import、
#      不展开宏，因此不抓类型错误。
#
#   2. 类型层（--typecheck，需要完整 Xcode）
#      复制源码到临时目录，用 scripts/l10n/typecheck/SparkleStub.swift 顶替 SPM 依赖 Sparkle，
#      再 swiftc -typecheck 做整模块类型检查。
#      之所以需要 Xcode：SwiftUI 的 @State/@Bindable/@Environment 等是外部宏，其实现在
#      Xcode 工具链的 libSwiftUIMacros.dylib 里，Command Line Tools 只带 Observation 与 Swift 宏。
#
# 用法：
#   scripts/l10n/typecheck.sh              # 语法检查
#   scripts/l10n/typecheck.sh --typecheck  # 类型检查（无 Xcode 会明确报错退出）
#
# 注意：这不是测试，也不产出二进制。真正的构建与单测仍须 Xcode；本脚本的价值是秒级反馈。

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SRC="$ROOT/Compositor"
PRIMARY="$ROOT/Compositor.xcodeproj"
STUB="$ROOT/scripts/l10n/typecheck/SparkleStub.swift"
TARGET="arm64-apple-macos26.0"
MODE="${1:-syntax}"

if [[ ! -d "$SRC" ]]; then
    echo "找不到源码目录：$SRC" >&2
    exit 2
fi

have_xcode() {
    local dev
    dev="$(xcode-select -p 2>/dev/null)" || return 1
    [[ "$dev" == *"Xcode.app"* ]] && return 0
    return 1
}

# ── 语法层 ────────────────────────────────────────────────────────────────
if [[ "$MODE" != "--typecheck" ]]; then
    echo "▸ 语法检查（swiftc -parse）"
    if xcrun --sdk macosx swiftc -parse -parse-as-library -swift-version 5 -target "$TARGET" \
            $(/usr/bin/find "$SRC" -name '*.swift') 2>&1 | tee /tmp/compositor-parse.log | grep -q 'error:'; then
        echo "❌ 语法错误：" >&2
        grep -A 2 'error:' /tmp/compositor-parse.log | head -40 >&2
        exit 1
    fi
    echo "✅ 语法检查通过（$(/usr/bin/find "$SRC" -name '*.swift' | wc -l | tr -d ' ') 个文件）"
    echo "  提示：语法层不抓类型错误。装好 Xcode 后跑 --typecheck 与 xcodebuild test。"
    exit 0
fi

# ── 类型层 ────────────────────────────────────────────────────────────────
if ! have_xcode; then
    cat >&2 <<'MSG'
❌ 类型检查需要完整 Xcode，当前只有 Command Line Tools。

   原因：SwiftUI 的 @State / @Bindable / @Environment 等是外部宏，实现位于
   Xcode 工具链的 libSwiftUIMacros.dylib；Command Line Tools 只提供
   libObservationMacros.dylib（@Observable）与 libSwiftMacros.dylib。

   装好 Xcode 后执行：
     sudo xcode-select -s /Applications/Xcode.app
     scripts/l10n/typecheck.sh --typecheck

   在此之前可用默认的语法检查：scripts/l10n/typecheck.sh
MSG
    exit 3
fi

SCRATCH="$(mktemp -d "${TMPDIR:-/tmp}/compositor-typecheck.XXXXXX")"
trap 'rm -rf "$SCRATCH"' EXIT

echo "▸ 复制源码到临时目录"
mkdir -p "$SCRATCH/src"
cp -R "$SRC"/. "$SCRATCH/src/"

/usr/bin/find "$SCRATCH/src" -name '*.swift' -exec sed -i '' -e '/^import Sparkle$/d' {} +
cp "$STUB" "$SCRATCH/src/SparkleStub.swift"

COUNT=$(( $(/usr/bin/find "$SCRATCH/src" -name '*.swift' | wc -l | tr -d ' ') - 1 ))
echo "▸ 类型检查 $COUNT 个源文件"
if xcrun --sdk macosx swiftc -typecheck -parse-as-library -swift-version 5 -target "$TARGET" \
        $(/usr/bin/find "$SCRATCH/src" -name '*.swift') 2> "$SCRATCH/errors.txt"; then
    echo "✅ 类型检查通过"
    exit 0
fi

echo "❌ 类型检查失败：" >&2
sed -e "s|$SCRATCH/src/||g" "$SCRATCH/errors.txt" >&2
exit 1
