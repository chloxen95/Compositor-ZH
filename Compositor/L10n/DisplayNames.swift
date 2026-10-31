import Foundation

// 显示名与线上身份的分工
// =====================
//
// 工程里有一批字符串枚举，`rawValue` 同时是文件格式。项目文件是 manifest.json
// （JSONEncoder 直出），里面的 `"blendMode": "Multiply"` 就是 rawValue。所以：
//
//   · rawValue **永久冻结**：它是工程文件、拖拽载荷、图片资源名、偏好键的身份。
//     改动它的后果不是报错，而是中文版存的工程英文版打不开，且没有任何提示。
//     锁它的是 scripts/l10n/wirecheck.py（l10n/wire-format.json 是它的指纹）。
//
//   · displayName 才是给人看的字。它走 String Catalog，跟着界面语言变。
//
// 为什么要写成穷举 switch，而不是 `String(localized: rawValue)` 一行了事：
// 编译器会在上游新增一个取值时停在这里。上游合并进来时，那一个编译错误就是
// 「这里还有一句要翻」的待办，比跑一遍全量扫描更早、更准。
//
// 句子里带名字的地方（撤销动作、提示语）不能用字符串拼接：`"Add " + name` 在
// 中文里语序不同，而且拼出来的片段永远进不了翻译表。这类地方一律用整句键 + %@，
// 见 `localizedSentence`。

/// 把已经本地化的名字填进本地化句型，键里用 `%@`。
///
///     localizedSentence("Add %@", effect.displayName)   // 英文 Add Drop Shadow，中文 添加投影
///
/// 之所以不让调用方自己拼，见文件头：拼接会把语序写死在代码里。
nonisolated func localizedSentence(_ key: String.LocalizationValue, _ name: String) -> String {
    String(format: String(localized: key), name)
}
