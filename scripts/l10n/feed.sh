#!/bin/zsh
# 管理简体中文版的自动更新源（fork 上的 update-feed 分支）。
#
#   scripts/l10n/feed.sh check     检查配置是否自洽：feed 地址、可达性、XML、密钥是否已轮换
#   scripts/l10n/feed.sh key       生成我们自己的 EdDSA 密钥并写入 Info.plist
#   scripts/l10n/feed.sh tools     下载并校验 Sparkle 官方命令行工具（generate_keys / sign_update）
#   scripts/l10n/feed.sh publish   把已签名的 DMG 写进 feed 分支
#
# 为什么更新源要独立于上游：
#   上游把 appcast.xml 放在 main 上，每次发版都改写它。我们的 hans 分支要定期合并
#   上游 main，如果 feed 也放在 hans，每次合并都会在这个文件上冲突。放在独立分支
#   之后两边互不相干，合并永远不碰它。
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
PLIST="$PROJECT_DIR/Config/Info.plist"
# 分支名不能叫 feed：raw 会把路径第三段同时当作分支名和提交 SHA 前缀，
# 而 feed 是合法十六进制，会静默命中 2026-09-21 的提交 feedc263fc…。
FEED_BRANCH=update-feed
# 用频道标题做归属标记：读到别人的旧公告时标题对不上，立刻能发现。
FEED_MARKER="Compositor 简体中文"
UPSTREAM_KEY="KZvD724t8QpzTR4OGrHrsCWt538TJ/g/qrTZii+o214="

# Sparkle 的命令行工具（generate_keys / sign_update / generate_appcast）不在系统里，
# 只在两种地方出现：SPM 解析后的 artifact bundle，或官方发行包。前者要求先跑构建，
# 而且会随 DerivedData 被清掉；后者可以独立取得，更适合脚本。
# 版本必须与 Package.resolved 锁定的 revision 一致（2.10.0）。
SPARKLE_VERSION=2.10.0
SPARKLE_SHA256=c2bf58aa8387266ac179357b1415d6f2635f044da8be41042af32425dae6da0c
TOOLS_DIR="$HOME/Library/Caches/CompositorZH/Sparkle-tools"
# 私钥备份放在 Application Support 而不是 Documents：后者默认同步 iCloud，
# 私钥不该进任何云端。这里只在 Time Machine 备份范围内。
KEY_BACKUP_DIR="$HOME/Library/Application Support/CompositorZH/signing"

die() { print -u2 -- "❌ $*"; exit 1 }
info() { print -r -- "▸ $*" }
warn() { print -u2 -- "⚠️  $*" }

repo_slug() {
    local url
    url=$(git -C "$PROJECT_DIR" remote get-url origin 2>/dev/null) \
        || die "没有名为 origin 的远端。先执行：git remote add origin https://github.com/<你>/<仓库>.git"
    print -r -- "$url" | sed -E 's#^(https://github.com/|git@github.com:)##; s#\.git$##'
}

expected_feed_url() { print -r -- "https://raw.githubusercontent.com/$1/$FEED_BRANCH/appcast.xml" }
plist_get() { plutil -extract "$1" raw "$PLIST" 2>/dev/null || print -r -- "" }

# 只改 SUPublicEDKey 那一行的值，不用 plutil -replace。
# 原因：任何结构化 plist 写入（plutil、PlistBuddy、PropertyListSerialization）
# 都会按字母序重排键、并丢掉 XML 注释。这里的注释解释了为什么更新源指向 fork，
# 键序也是上游原样；改动越"干净"，合并上游时越不会冲突。
set_public_key() {
    local key=$1
    /usr/bin/python3 - "$PLIST" "$key" <<'PY'
import re, sys
path, key = sys.argv[1], sys.argv[2]
text = open(path, encoding="utf-8").read()
pattern = re.compile(r"(<key>SUPublicEDKey</key>\s*<string>)(.*?)(</string>)", re.S)
found = pattern.findall(text)
if len(found) != 1:
    sys.exit(f"SUPublicEDKey 应恰好出现一次，实际 {len(found)} 次")
updated = pattern.sub(lambda m: m.group(1) + key + m.group(3), text, count=1)
if updated == text:
    print("值未变化，文件未改动")
else:
    open(path, "w", encoding="utf-8").write(updated)
    print("已就地替换 SUPublicEDKey（保留注释与键序）")
PY
}

find_tool() {
    local name=$1 candidate
    for candidate in \
        "$TOOLS_DIR/bin/$name" \
        "$HOME/Library/Caches/CompositorZH/SourcePackages/artifacts/sparkle/Sparkle/bin/$name" \
        "$HOME/Library/Caches/CompositorRelease/DerivedData/SourcePackages/artifacts/sparkle/Sparkle/bin/$name" \
        $HOME/Library/Developer/Xcode/DerivedData/*/SourcePackages/artifacts/sparkle/Sparkle/bin/$name(N)
    do
        [[ -x "$candidate" ]] && { print -r -- "$candidate"; return 0 }
    done
    return 1
}

# ── tools ─────────────────────────────────────────────────────────────────
# 取官方发行包里的命令行工具。校验和写死在上面：版本一旦被换掉就会直接失败，
# 而不是静默地用一个来路不明的二进制去签更新包。
cmd_tools() {
    local name
    if [[ -x "$TOOLS_DIR/bin/generate_keys" && -x "$TOOLS_DIR/bin/sign_update" ]]; then
        print -r -- "✅ 工具已在：$TOOLS_DIR/bin"
        return 0
    fi

    local tmp
    tmp=$(mktemp -d)
    trap "rm -rf '$tmp'" EXIT
    info "下载 Sparkle $SPARKLE_VERSION 官方发行包"
    curl -fsSL --retry 4 --retry-delay 2 --max-time 240 \
        -o "$tmp/Sparkle.tar.xz" \
        "https://github.com/sparkle-project/Sparkle/releases/download/$SPARKLE_VERSION/Sparkle-$SPARKLE_VERSION.tar.xz" \
        || die "下载失败。检查网络（可能需要 VPN），或手动把工具放进 $TOOLS_DIR/bin"

    local actual
    actual=$(shasum -a 256 "$tmp/Sparkle.tar.xz" | awk '{print $1}')
    [[ "$actual" == "$SPARKLE_SHA256" ]] \
        || die "校验和不符：期望 $SPARKLE_SHA256，实际 $actual。拒绝使用被替换的发行包。"

    tar -xf "$tmp/Sparkle.tar.xz" -C "$tmp"
    mkdir -p "$TOOLS_DIR/bin"
    /bin/cp "$tmp/bin/generate_keys" "$tmp/bin/sign_update" "$tmp/bin/generate_appcast" "$TOOLS_DIR/bin/"
    chmod +x "$TOOLS_DIR/bin/"*
    print -r -- "✅ 已解压到 $TOOLS_DIR/bin（校验和通过）"
}

# ── check ─────────────────────────────────────────────────────────────────
cmd_check() {
    local slug feed configured pubkey errors=0
    slug=$(repo_slug) || exit 1
    feed=$(expected_feed_url "$slug")
    configured=$(plist_get SUFeedURL)
    pubkey=$(plist_get SUPublicEDKey)

    info "仓库：$slug"
    info "应指向：$feed"
    info "实际指向：$configured"
    if [[ "$configured" != "$feed" ]]; then
        print -u2 -- "❌ Info.plist 的 SUFeedURL 与实际仓库不一致"
        errors=$((errors + 1))
    else
        print -r -- "✅ SUFeedURL 与 origin 一致"
    fi

    if [[ "$pubkey" == "$UPSTREAM_KEY" ]]; then
        warn "SUPublicEDKey 仍是上游的公钥：我们还签不出能通过校验的更新包。"
        warn "  发布第一个汉化版之前必须轮换：scripts/l10n/feed.sh key"
    else
        print -r -- "✅ SUPublicEDKey 已换成我们自己的密钥"
    fi

    info "检查 feed 可达性"
    local body
    if body=$(curl -fsS --max-time 12 "$feed" 2>/dev/null); then
        local report
        report=$(print -r -- "$body" | FEED_MARKER="$FEED_MARKER" /usr/bin/python3 -c '
import os, sys, xml.etree.ElementTree as ET
try:
    root = ET.fromstring(sys.stdin.read())
except Exception:
    print("INVALID|0"); raise SystemExit(0)
title = (root.findtext("channel/title") or "").strip()
print(("OK" if title == os.environ["FEED_MARKER"] else "FOREIGN") + "|" + str(len(root.findall("channel/item"))))
' 2>/dev/null)
        local state=${report%%|*} items=${report##*|}
        case "$state" in
            INVALID) print -u2 -- "❌ feed 不是合法 XML"; errors=$((errors + 1)) ;;
            FOREIGN)
                print -u2 -- "❌ feed 能访问，但不是我们的公告（标题不是「$FEED_MARKER」）"
                print -u2 -- "   这是被同名解析劫持的典型症状：raw 把路径第三段当成了提交 SHA 前缀。"
                print -u2 -- "   别用只由 0-9a-f 组成的分支名（feed / dead / beef / cafe…）。"
                errors=$((errors + 1)) ;;
            *)
                if [[ "$items" == "0" ]]; then
                    print -r -- "✅ 是我们的公告；目前 0 个版本项（等同「已是最新」）"
                else
                    print -r -- "✅ 是我们的公告；$items 个版本项"
                fi ;;
        esac
    else
        print -u2 -- "❌ feed 取不到（分支未推送，或仓库不是公开的）"
        print -u2 -- "   推送：git push origin $FEED_BRANCH"
        errors=$((errors + 1))
    fi

    print -r --
    if (( errors )); then
        print -r -- "结论：$errors 项待处理"
        return 1
    fi
    print -r -- "结论：配置自洽"
}

# ── key ───────────────────────────────────────────────────────────────────
# 生成（或复用）Ed25519 密钥对，把公钥写进 Info.plist，并导出一份私钥备份。
# 幂等：钥匙串里已有密钥时不覆盖，只重新确认公钥并同步到 plist。
cmd_key() {
    local generate pubkey previous backup
    generate=$(find_tool generate_keys) \
        || die "找不到 generate_keys。先执行：scripts/l10n/feed.sh tools"

    previous=$(plist_get SUPublicEDKey)

    info "生成 Ed25519 密钥对（私钥进登录钥匙串，不写进仓库）"
    # 无参数时：没有密钥就新建，已有则复用。输出是给人读的说明段落，丢弃。
    "$generate" >/dev/null 2>&1 \
        || die "generate_keys 失败。若钥匙串授权框被拒绝，重跑一次并选「始终允许」。"

    # 用 -p 取公钥：默认模式的输出是多行说明文字，解析不可靠。
    pubkey=$("$generate" -p 2>/dev/null | tr -d '[:space:]')
    [[ "$pubkey" =~ ^[A-Za-z0-9+/]{43}=$ ]] \
        || die "公钥格式异常：'$pubkey'（期望 44 字符 base64）"

    set_public_key "$pubkey"
    plutil -lint "$PLIST" >/dev/null || die "写入后 plist 不合法，请检查 $PLIST"
    print -r -- "✅ SUPublicEDKey = $pubkey"

    if [[ "$pubkey" == "$UPSTREAM_KEY" ]]; then
        warn "新公钥与上游相同，这不正常：钥匙串里可能存在上游的私钥。"
    fi
    if [[ -n "$previous" && "$previous" != "$pubkey" ]]; then
        warn "公钥已变更：$previous → $pubkey"
        warn "  已装出的旧版仍内嵌旧公钥，收不到新版更新，需手动重装一次。"
    fi

    # 私钥必须留备份：丢了就再也签不出能通过校验的更新包。
    mkdir -p "$KEY_BACKUP_DIR"
    chmod 700 "$KEY_BACKUP_DIR"
    backup="$KEY_BACKUP_DIR/ed25519-private-key.txt"
    if [[ -f "$backup" ]]; then
        print -r -- "▸ 私钥备份已存在，未覆盖：$backup"
    elif "$generate" -x "$backup" >/dev/null 2>&1; then
        chmod 600 "$backup"
        print -r -- "✅ 私钥已备份：$backup"
    else
        warn "私钥自动导出失败。手动执行：$generate -x <目标文件>"
    fi

    # 自检：真签一个文件，再用 CryptoKit 独立验签。
    # 公钥配错在用户端表现为「静默装不上」，所以这事必须当场证明，不能靠肉眼比对字符串。
    local sign verifier probe sig
    sign=$(find_tool sign_update) || die "缺少 sign_update，无法验签：scripts/l10n/feed.sh tools"
    verifier="$PROJECT_DIR/scripts/l10n/verify-ed25519.swift"
    [[ -f "$verifier" ]] || die "缺少验签脚本：$verifier"

    probe=$(mktemp -d)
    printf 'compositor-zh signing self-test\n' > "$probe/payload.bin"
    sig=$("$sign" "$probe/payload.bin" | sed -E 's/.*edSignature="([^"]+)".*/\1/')
    if xcrun swift "$verifier" "$pubkey" "$probe/payload.bin" "$sig" 2>&1 | grep -q "验签通过"; then
        print -r -- "✅ 验签自检通过：钥匙串私钥与 plist 公钥确为同一对"
    else
        rm -rf "$probe"
        die "验签自检失败：私钥与公钥不匹配，此时发布的更新包用户装不上。切勿发布。"
    fi
    rm -rf "$probe"

    print -r --
    print -r -- "下一步："
    print -r -- "  1. 把 $KEY_BACKUP_DIR 复制到离线介质或密码管理器（丢了更新链就断）"
    print -r -- "  2. 重新构建：scripts/l10n/build-zh.sh"
    print -r -- "  3. 发布签名见 l10n/RELEASE.md"
}

# ── publish ───────────────────────────────────────────────────────────────
cmd_publish() {
    local dmg=${1:-} url=${2:-} build=${3:-} version=${4:-}
    shift 4 2>/dev/null || true
    local notes=("$@")
    [[ -f "$dmg" ]] || die "用法：feed.sh publish <dmg> <下载地址> <build 号> <版本号> [变更说明…]"
    [[ -n "$url" ]] || die "缺少下载地址"
    [[ "$build" =~ ^[0-9]+$ ]] || die "build 号必须是整数（Sparkle 用它比较新旧）"

    local sign signature
    sign=$(find_tool sign_update) || die "找不到 Sparkle 的 sign_update，先跑 scripts/release.sh 或 build-zh.sh"
    info "签名 $dmg"
    signature=$("$sign" "$dmg")

    local work
    work=$(mktemp -d)
    trap "git -C '$PROJECT_DIR' worktree remove --force '$work' >/dev/null 2>&1 || rm -rf '$work'" EXIT
    git -C "$PROJECT_DIR" worktree add -q "$work" "$FEED_BRANCH" 2>/dev/null \
        || git -C "$PROJECT_DIR" worktree add -q --orphan -b "$FEED_BRANCH" "$work"

    /usr/bin/python3 - "$work/appcast.xml" "$version" "$build" "$url" "$signature" "${notes[@]}" <<'PY'
import sys, datetime, html
path, version, build, url, signature, *notes = sys.argv[1:]
changes = ""
if notes:
    body = "\n".join(notes)
    changes = f"\n      <changes><![CDATA[{body}]]></changes>"
stamp = datetime.datetime.now(datetime.timezone.utc).strftime("%a, %d %b %Y %H:%M:%S +0000")
xml = f'''<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Compositor 简体中文</title>
    <item>
      <title>Version {version}</title>
      <pubDate>{stamp}</pubDate>
      <sparkle:version>{build}</sparkle:version>
      <sparkle:shortVersionString>{version}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>26.0</sparkle:minimumSystemVersion>{changes}
      <enclosure url="{url}" {signature} type="application/octet-stream"/>
    </item>
  </channel>
</rss>
'''
open(path, "w", encoding="utf-8").write(xml)
print(f"已写入 item：{version} (build {build})")
PY

    git -C "$work" add appcast.xml
    git -C "$work" commit -q -m "feed: publish $version ($build)"
    print -r -- "✅ feed 分支已更新"
    print -r -- "推送后生效：git -C '$PROJECT_DIR' push origin $FEED_BRANCH"
}

case "${1:-}" in
    check)   shift; cmd_check "$@" ;;
    key)     shift; cmd_key "$@" ;;
    tools)   shift; cmd_tools "$@" ;;
    publish) shift; cmd_publish "$@" ;;
    *)       print -u2 -- "用法：feed.sh check | key | tools | publish <dmg> <url> <build> <version> [说明…]"; exit 2 ;;
esac
