# 简体中文版：发布与维护手册

适用仓库：`https://github.com/chloxen95/Compositor-ZH`（fork 自 `robbietilton/Compositor`）

---

## 一、分支与远端的约定

| 名称 | 作用 | 是否提交汉化代码 |
|---|---|---|
| `upstream` | 上游 `robbietilton/Compositor`，只读 | — |
| `origin` | 你的 fork `chloxen95/Compositor-ZH` | — |
| `main` | 上游的纯净镜像，只做 `git pull upstream main` | **否** |
| `hans` | 汉化分支，所有工作在这里 | 是 |
| `update-feed` | 只放 `appcast.xml`（自动更新源） | 否（只有 feed） |

`update-feed` 必须独立，因为上游每次发版都会改写它 `main` 上的 `appcast.xml`；
放在 `hans` 里会导致每次合并上游都冲突。

---

## 二、一次性设置（顺序不能颠倒）

### 1. 推送两个分支

```bash
cd "/Users/chenhanlin/WorkBuddy/Compositor 汉化/Compositor"
git push -u origin hans
git push origin update-feed
```

> **先推 `update-feed`，再运行编译出来的 App。**
> 应用启动时会去读这个地址，未推送时是 404，Sparkle 会在日志里报错（不会弹窗、不会装错东西，
> 但配置不算就绪）。

### 2. 准备 Sparkle 命令行工具

```bash
./scripts/l10n/feed.sh tools
```

下载 Sparkle 2.10.0 官方发行包里的 `generate_keys` / `sign_update` / `generate_appcast`，
解压到 `~/Library/Caches/CompositorZH/Sparkle-tools/bin`。发行包带 SHA-256 校验，
版本与 `Package.resolved` 锁定的 revision（2.10.0）一致；包被换掉会直接失败，不会静默使用。

> 这些工具在 SPM 解析后的 artifact bundle 里也有，但那要求先构建成功一次，
> 而且会随 DerivedData 被清掉。独立下载更稳，也不依赖 Xcode 是否装好。

### 3. 生成我们自己的更新签名密钥

```bash
./scripts/l10n/feed.sh key
```

幂等：钥匙串里已有密钥就复用，不覆盖。它做四件事：

1. 生成 Ed25519 密钥对，私钥存进登录钥匙串（服务 `https://sparkle-project.org`，账户 `ed25519`）；
2. 把公钥写进 `Config/Info.plist` 的 `SUPublicEDKey`——**只改这一行**，注释与键序原样保留。
   （不用 `plutil -replace`：它按字母序重排整个文件并丢掉 XML 注释，那样每次合并上游都要多解一次冲突。）
3. 导出私钥到 `~/Library/Application Support/CompositorZH/signing/ed25519-private-key.txt`（600 权限）；
4. 真签一个测试文件，再用 CryptoKit 独立验签，确认私钥与公钥确实配对。

**为什么必须换掉**：留着上游的公钥，我们既签不出自己的更新，又等于给上游的英文包开了后门。

**私钥必须另存一份离线备份**。丢了就再也签不出能通过校验的更新包，已装旧版的用户只能手动重装。
备份目录特意放在 `Application Support` 而不是 `Documents`：后者默认同步 iCloud，私钥不该进任何云端。

> `SUEnableAutomaticChecks` 沿用上游的 `<true/>`，无需改动。

### 4. 单独验证密钥（可选，`key` 已自动执行）

```bash
PUB=$(plutil -extract SUPublicEDKey raw Config/Info.plist)
printf 'selftest\n' > /tmp/selftest.bin
SIG=$("$HOME/Library/Caches/CompositorZH/Sparkle-tools/bin/sign_update" /tmp/selftest.bin \
      | sed -E 's/.*edSignature="([^"]+)".*/\1/')
xcrun swift scripts/l10n/verify-ed25519.swift "$PUB" /tmp/selftest.bin "$SIG"
```

输出「✅ 验签通过」表示钥匙串私钥与 plist 公钥是同一对。

用 CryptoKit 而不是 Sparkle 自己的代码，是因为**用签名工具去验自己的签名等于没验**。
公钥配错在用户端的表现不是报错，而是静默装不上，所以必须用独立实现证一次。

### 5. 验证配置自洽

```bash
./scripts/l10n/feed.sh check
```

全部通过时应显示「结论：配置自洽」。

---

## 三、日常：编译自用

```bash
./scripts/l10n/build-zh.sh            # 首次汉化版，build = 上游 ×10 + 1
ZH_REV=2 ./scripts/l10n/build-zh.sh   # 同一上游基线上再发一版
```

产物在 `~/Library/Caches/CompositorZH/Build/Products/Release/Compositor.app`。
本机自用无需证书，脚本会打印 `open` 命令。

版本号采用「上游 build × 10 + 汉化修订号」：上游 58 的第 1 个汉化版是 581。
这样既单调递增，又能一眼看出基于哪个上游版本。**版本号由命令行注入，不写进工程文件**，
避免与上游每次发版对同一行产生冲突。

---

## 四、发布：让用户能自动更新

### 1. 打包成 DMG

需要 Developer ID 证书与公证（否则别人下载会被 Gatekeeper 拦）。
上游的 `scripts/release.sh` 里写死了他自己的 Team ID（`3E4X3B9Z9T`），
用之前必须改成你的，或复制一份改成 `scripts/l10n/release-zh.sh`。

### 2. 上传 DMG

传到 GitHub Releases，例如 tag `zh-581`，文件命名保持 `Compositor.dmg`。
没有 `gh` 命令行时可以在网页上手动拖拽上传。

### 3. 写进更新源

```bash
./scripts/l10n/feed.sh publish \
  dist/Compositor-1.5.12.dmg \
  https://github.com/chloxen95/Compositor-ZH/releases/download/zh-581/Compositor.dmg \
  581 1.5.12 \
  "首个简体中文版" "图层、蒙版、Camera Raw 面板已汉化"

git push origin update-feed
```

脚本会调用 Sparkle 的 `sign_update` 生成签名与长度，写入 `update-feed` 分支。

---

## 五、跟随上游

```bash
git fetch upstream
git checkout main && git merge --ff-only upstream/main
git checkout hans && git merge main          # 有冲突就解，解完跑下面三条
./scripts/l10n/typecheck.sh --typecheck      # 类型层；不加参数是语法层，更快
python3 scripts/l10n/extract.py --csv l10n/translations.csv   # 看新增/孤儿
python3 scripts/l10n/lint.py
```

- 只用 **merge**，不用 rebase：rebase 要反复解同一批冲突。
- 合并后 `extract.py` 会报新增 key 与孤儿 key。孤儿不要删，是上游改了英文句子，
  用旧译文做模糊匹配比重新翻便宜。
- 每次合并打 tag（如 `upstream-1.5.13`），便于定位。

---

## 六、故障排查

| 现象 | 原因 | 处理 |
|---|---|---|
| `feed.sh check` 报「取不到」 | `update-feed` 还没推送，或仓库不是公开的 | `git push origin update-feed` |
| 报「不是我们的公告（标题不是 …）」 | 分支名撞上了提交 SHA 前缀 | 见下节；改回 `update-feed` |
| 找不到 `generate_keys` / `sign_update` | 工具还没下载 | `./scripts/l10n/feed.sh tools`（需联网，可能要 VPN） |
| `feed.sh key` 报「验签自检失败」 | 钥匙串私钥与 plist 公钥不配对 | 重跑 `feed.sh key`；仍失败则删掉钥匙串里 `ed25519` 条目后重新生成 |
| 应用提示更新但安装失败 | `SUPublicEDKey` 还是上游的公钥 | `./scripts/l10n/feed.sh key` 后重新构建 |
| 更新装完变回英文 | `SUFeedURL` 指到了上游 | `feed.sh check` 核对 |
| 合并上游时 `appcast.xml` 冲突 | feed 被放进了 `hans` | 把该文件移回 `update-feed` 分支 |
| `xcodebuild` 报「a required plug-in failed to load」 | Xcode 首启动组件没装（缺 CoreSimulator） | `sudo xcodebuild -runFirstLaunch`，需管理员密码 |

### 分支名为什么不能叫 `feed`

`raw.githubusercontent.com/{owner}/{repo}/{段}/{路径}` 的第三段**既可以是分支名，
也可以是提交 SHA 的前缀**。`feed` 全由十六进制字符组成，恰好匹配 2026-09-21 的提交
`feedc263fc…`，于是 `/feed/appcast.xml` 会静默返回那份旧公告（Version 1.1.8、build 14、
指向上游的 DMG）。

危害不在于那份公告本身（build 14 低于我们的 58，不会触发安装），而在于**应用会去读一份我们
不控制的文件**。哪天命中一个版本号更高的旧公告，就会把上游的英文包装进来。

凡是只由 `0-9a-f` 组成的名字都有这个问题：`feed`、`dead`、`beef`、`cafe`、`face`、`decade`。
`update-feed` 含 `u`、`p`、`t`、`-`，不可能与 SHA 前缀混淆。
`feed.sh check` 会核对频道标题必须是 `Compositor 简体中文`，专门用来抓这类劫持。
