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

### 2. 生成我们自己的更新签名密钥

```bash
./scripts/l10n/feed.sh key
```

这一步需要完整 Xcode（用 Sparkle 官方的 `generate_keys`）。它做两件事：
把公钥写进 `Config/Info.plist` 的 `SUPublicEDKey`，并提示你备份私钥。

**为什么必须换掉**：`SUPublicEDKey` 现在还是上游的公钥。Sparkle 只认「与包内公钥配对的私钥」
签出的更新包。留着上游的公钥，我们既签不出自己的更新，又等于给上游的英文包开了后门。

**私钥必须备份**（登录钥匙串里名为 `ed25519` 的条目，导出为 `.p8` 存好）。
私钥丢了，已经装了旧版的用户就再也收不到自动更新，只能手动重装。

### 3. 打开自动检查

`Config/Info.plist` 里把 `SUEnableAutomaticChecks` 设为 `<true/>`，然后重新构建。

### 4. 验证配置自洽

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
git checkout hans && git merge main          # 有冲突就解，解完跑下面两条
./scripts/l10n/typecheck.sh
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
| 应用提示更新但安装失败 | `SUPublicEDKey` 还是上游的公钥 | `./scripts/l10n/feed.sh key` 后重新构建 |
| 更新装完变回英文 | `SUFeedURL` 指到了上游 | `feed.sh check` 核对 |
| 合并上游时 `appcast.xml` 冲突 | feed 被放进了 `hans` | 把该文件移回 `update-feed` 分支 |

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
