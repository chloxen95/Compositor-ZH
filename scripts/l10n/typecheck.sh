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
#
#      需要 Xcode 的原因只有一个：SwiftUI 的 @State/@Bindable 等是外部宏，实现在
#      Xcode 的平台插件里（MacOSX.platform/.../host/plugins/libSwiftUIMacros.dylib），
#      Command Line Tools 只带 Observation 与 Swift 宏。因此要显式 -plugin-path。
#
#      另外必须补齐工程的并发设置：pbxproj 里 SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor、
#      SWIFT_APPROACHABLE_CONCURRENCY = YES。不补的话，编译器不认为类型默认在 MainActor 上，
#      会把 normal 代码调用 @MainActor API 当成错误，报出一批与真实问题无关的假错。
#
#      它不依赖 xcodebuild，因此 Xcode 首启动组件没装好时（缺 CoreSimulator）也能用。
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

# 去掉 import Sparkle，改用桩。用 python 而不是 sed -i：BSD sed 的 -i 参数
# 与 -exec {} + 组合会多打印一行 "sed: : No such file or directory"，容易误判为失败。
/usr/bin/python3 - "$SCRATCH/src" <<'PY'
import pathlib, sys
root = pathlib.Path(sys.argv[1])
stripped = 0
for path in root.rglob("*.swift"):
    text = path.read_text(encoding="utf-8")
    if "import Sparkle\n" in text:
        path.write_text(text.replace("import Sparkle\n", "", 1), encoding="utf-8")
        stripped += 1
print(f"  已用桩替换 import Sparkle 的文件：{stripped}")
PY
cp "$STUB" "$SCRATCH/src/SparkleStub.swift"

# 编译选项必须与 pbxproj 一致，否则会报假错（见文件头说明）。
DEV_DIR="$(xcode-select -p 2>/dev/null)"
PLUGIN_PATH="$DEV_DIR/Platforms/MacOSX.platform/Developer/usr/lib/swift/host/plugins"
EXTRA=()
[[ -d "$PLUGIN_PATH" ]] && EXTRA+=(-plugin-path "$PLUGIN_PATH")
if xcrun --sdk macosx swiftc -help-hidden 2>&1 | grep -q -- '-default-isolation'; then
    EXTRA+=(-default-isolation MainActor)
fi
EXTRA+=(-enable-upcoming-feature MemberImportVisibility)
EXTRA+=(-enable-upcoming-feature NonisolatedNonsendingByDefault)
EXTRA+=(-enable-upcoming-feature InferIsolatedConformances)

# 工程的像素运算在 C 里（10 个 .c + 11 个 .h），Swift 通过桥接头调用。
# 不引入桥接头的话，dither_quantize16 之类的符号会报 "cannot find in scope"。
BRIDGING="$SCRATCH/src/Compositor-Bridging-Header.h"
if [[ -f "$BRIDGING" ]]; then
    EXTRA+=(-import-objc-header "$BRIDGING")
    EXTRA+=(-Xcc -I -Xcc "$SCRATCH/src/Rendering")
else
    echo "⚠️  找不到桥接头 Compositor-Bridging-Header.h，C 函数会报未定义" >&2
fi

COUNT=$(( $(/usr/bin/find "$SCRATCH/src" -name '*.swift' | wc -l | tr -d ' ') - 1 ))
echo "▸ 类型检查 $COUNT 个源文件（宏插件：$([[ -d "$PLUGIN_PATH" ]] && echo 已加载 || echo 缺失)）"
if xcrun --sdk macosx swiftc -typecheck -parse-as-library -swift-version 5 -target "$TARGET" \
        "${EXTRA[@]}" \
        $(/usr/bin/find "$SCRATCH/src" -name '*.swift') 2> "$SCRATCH/errors.txt"; then
    echo "✅ 类型检查通过"
    exit 0
fi

echo "❌ 类型检查失败：" >&2
sed -e "s|$SCRATCH/src/||g" "$SCRATCH/errors.txt" >&2
exit 1
