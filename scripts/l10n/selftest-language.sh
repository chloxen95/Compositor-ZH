#!/bin/zsh
# 编译并运行语言偏好的自检程序。
#
# 不走 xcodebuild test：受限会话里测试宿主起不来（见 l10n/RELEASE.md §六）。
# 这里只把 LanguagePreference.swift 和自检 main 编成一个独立可执行文件，
# 不需要 App、不需要测试宿主、不需要签名，退出码即结论。
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="${TMPDIR:-/tmp}/compositor-language-selftest"

xcrun swiftc -O \
    "$PROJECT_DIR/Compositor/App/LanguagePreference.swift" \
    "$PROJECT_DIR/scripts/l10n/selftest-language.swift" \
    -o "$OUT"

"$OUT"
