# update-feed 分支

这个分支只放一个文件：`appcast.xml`，即 Compositor 简体中文版的 Sparkle 自动更新源。

读取地址：`https://raw.githubusercontent.com/chloxen95/Compositor-ZH/update-feed/appcast.xml`

**不要合并进 main 或 hans**，也不要在这个分支放别的文件。

---

## 为什么分支名不能叫 `feed`

这一条是用踩坑换来的，务必保留。

最初用的是 `feed` 分支。推送前做验证时发现：`/feed/appcast.xml` **已经能返回 200**，
内容却是一份 2026-09-21 的旧公告（Version 1.1.8、build 14、指向上游的 DMG）。
可是 `git ls-remote --heads` 和 GitHub 的分支列表都显示只有 `main`。

原因：`raw.githubusercontent.com/{owner}/{repo}/{段}/{路径}` 里的第三段，
**既可以当分支名，也可以当提交 SHA 的前缀**。而 `f`、`e`、`d` 都是十六进制字符，
`feed` 正好是这个提交的合法前缀：

```
feedc263fc…   Reject oversized Photoshop shape descriptors before converting…   2026-09-21
```

于是 `/feed/appcast.xml` 被解析成「取这个提交里的 appcast.xml」，静默命中旧文件。
上、下游两个仓库都能返回同一份内容，正是因为这个提交在两边都存在。

**危害**：应用会去读一份我们不控制的公告。当时那份是 build 14（低于我们的 58），
Sparkle 不会动作；但只要哪天命中一个版本号更高的旧公告，就会把上游的英文包装进来。

**规避**：分支名用 `update-feed`。`u`、`p`、`t`、`-` 都不是十六进制字符，
不可能与任何提交 SHA 前缀混淆。凡是分支名只由 `0-9a-f` 组成（`feed`、`dead`、
`beef`、`cafe`、`face`、`decade` 这类），都有同样的风险。

`scripts/l10n/feed.sh check` 会核对返回内容的 `<title>` 必须是
`Compositor 简体中文`，用来确认读到的是我们自己的公告，而不是被同名解析劫持。

---

## 为什么要单独开一个分支

上游把它的 `appcast.xml` 放在 `main` 上，每次发版都改写它。
我们的 `hans` 分支需要定期合并上游 `main`——如果 feed 也放在 `hans`，
上游每发一次版，合并时必然在这个文件上冲突。

独立分支之后：上游改上游的，我们改我们的，合并永远不碰它。

## 怎么更新

不要手改。用仓库里的脚本：

```bash
scripts/l10n/feed.sh publish <dmg 路径> <下载地址> <build 号> <版本号> [变更说明…]
```

它会用 Sparkle 的 `sign_update` 签名、计算长度，生成格式正确的 `<item>` 并提交到本分支，
最后提示推送命令。

## 空 feed 代表什么

没有 `<item>` = 没有可用更新。Sparkle 查询后什么也不做，等同于「已是最新」。
