// 验证 Sparkle 更新签名用的 Ed25519 密钥对是否配对。
//
// 背景：Sparkle 只认「与包内 SUPublicEDKey 配对的私钥」签出的更新包。配错的表现
// 不是报错，而是用户端静默装不上——所以这件事必须能当场验证，不能靠肉眼看字符串。
//
// 为什么用 CryptoKit 而不是 Sparkle 自己的代码：这是独立实现。用签名工具自己的
// 逻辑去验自己，等于没验。CryptoKit 是 Apple 的密码学框架，与 Sparkle 无关。
//
// 用法：
//   xcrun swift scripts/l10n/verify-ed25519.swift <公钥base64> <被签文件> <签名base64>
//
// 退出码：0 = 通过，1 = 不匹配，2 = 参数或格式错误。

import Foundation
import CryptoKit

func fail(_ message: String, code: Int32) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(code)
}

guard CommandLine.arguments.count == 4 else {
    fail("用法: verify-ed25519 <公钥base64> <文件> <签名base64>", code: 2)
}

let publicKeyBase64 = CommandLine.arguments[1]
let filePath = CommandLine.arguments[2]
let signatureBase64 = CommandLine.arguments[3]

guard let publicKeyData = Data(base64Encoded: publicKeyBase64) else {
    fail("公钥不是合法 base64：\(publicKeyBase64)", code: 2)
}
guard publicKeyData.count == 32 else {
    fail("公钥应为 32 字节（Ed25519），实际 \(publicKeyData.count) 字节", code: 2)
}
guard let signatureData = Data(base64Encoded: signatureBase64) else {
    fail("签名不是合法 base64", code: 2)
}

let fileData: Data
do {
    fileData = try Data(contentsOf: URL(fileURLWithPath: filePath))
} catch {
    fail("读不到文件 \(filePath)：\(error.localizedDescription)", code: 2)
}

let publicKey: Curve25519.Signing.PublicKey
do {
    publicKey = try Curve25519.Signing.PublicKey(rawRepresentation: publicKeyData)
} catch {
    fail("公钥无法构造：\(error.localizedDescription)", code: 2)
}

print("公钥 \(publicKeyData.count) 字节，待验文件 \(fileData.count) 字节")

if publicKey.isValidSignature(signatureData, for: fileData) {
    print("✅ 验签通过：钥匙串私钥产出的签名可被该公钥验证，密钥对确实配对")
    exit(0)
} else {
    print("❌ 验签失败：公钥与签名不匹配")
    exit(1)
}
