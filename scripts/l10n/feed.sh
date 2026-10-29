#!/bin/zsh
# 管理简体中文版的自动更新源（fork 上的 feed 分支）。
#
#   scripts/l10n/feed.sh check     检查配置是否自洽：feed 地址、可达性、XML、密钥是否已轮换
#   scripts/l10n/feed.sh key       生成我们自己的 EdDSA 密钥并写入 Info.plist（需要 Xcode）
#   scripts/l10n/feed.sh publish   把已签名的 DMG 写进 feed 分支（需要 Xcode 的 sign_update）
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

find_tool() {
    local name=$1 candidate
    for candidate in \
        "$HOME/Library/Caches/CompositorRelease/DerivedData/SourcePackages/artifacts/sparkle/Sparkle/bin/$name" \
        $HOME/Library/Developer/Xcode/DerivedData/*/SourcePackages/artifacts/sparkle/Sparkle/bin/$name(N)
    do
        [[ -x "$candidate" ]] && { print -r -- "$candidate"; return 0 }
    done
    return 1
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
cmd_key() {
    local generate pubkey
    xcode-select -p 2>/dev/null | grep -q "Xcode.app" \
        || die "生成密钥要用 Sparkle 官方的 generate_keys，需要完整 Xcode。装好后再跑。"

    generate=$(find_tool generate_keys) \
        || die "找不到 Sparkle 的 generate_keys。先跑一次构建让 SPM 解析依赖：scripts/l10n/build-zh.sh"

    info "生成 Ed25519 密钥对（私钥进登录钥匙串，不会写进仓库）"
    pubkey=$("$generate" -p 2>/dev/null || "$generate" 2>&1 | tail -1)
    [[ -n "$pubkey" ]] || die "generate_keys 没有输出公钥"

    plutil -replace SUPublicEDKey -string "$pubkey" "$PLIST"
    print -r -- "✅ 已写入 Config/Info.plist：SUPublicEDKey = $pubkey"
    print -r --
    warn "私钥在登录钥匙串里，条目名 ed25519。请立刻备份："
    warn "  钥匙串访问 → 搜索 ed25519 → 导出为 .p8 存到安全位置"
    warn "  私钥丢失后无法再为已安装的旧版签出更新，用户只能手动重装。"
    warn "  绝不能把私钥提交进仓库（.gitignore 已排除 *.p8）。"
    print -r --
    print -r -- "接着要把自动检查打开：把 Config/Info.plist 的 SUEnableAutomaticChecks 改为 <true/>，然后重新构建。"
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
    publish) shift; cmd_publish "$@" ;;
    *)       print -u2 -- "用法：feed.sh check | key | publish <dmg> <url> <build> <version> [说明…]"; exit 2 ;;
esac
