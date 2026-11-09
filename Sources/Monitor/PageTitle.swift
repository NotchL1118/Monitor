import Foundation

/// Display-only cleanup for page titles. Stored titles and JSON export keep the raw text.
enum PageTitle {
    static let mask = "••••••"
    private static let email = try! NSRegularExpression(pattern: #"[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}"#)
    private static let separators = try! NSRegularExpression(pattern: #"\s*([\-–—|·])\s*(?:[\-–—|·]\s*)+"#)
    private static let edges = try! NSRegularExpression(pattern: #"^[\s\-–—|·]+|[\s\-–—|·]+$"#)
    private static let codeContext = try! NSRegularExpression(
        pattern: #"验证码|校验码|安全码|动态码|确认码|登录码|verification|passcode|one[- ]time|\bOTP\b|\bcode\b|\bPIN\b"#,
        options: [.caseInsensitive])
    private static let code = try! NSRegularExpression(pattern: #"(?<![0-9])[0-9]{4,8}(?![0-9])"#)

    /// Removes e-mail addresses and masks one-time codes in titles that mention a code.
    static func display(_ raw: String) -> String {
        var text = raw
        if text.contains("@") {
            text = replace(email, in: text, with: "")
            text = replace(separators, in: text, with: " $1 ")
            text = replace(edges, in: text, with: "")
            if text.isEmpty { return "（邮箱地址已隐藏）" }
        }
        if codeContext.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil {
            text = replace(code, in: text, with: mask)
        }
        return text
    }

    private static func replace(_ expression: NSRegularExpression, in text: String, with template: String) -> String {
        expression.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: template)
    }
}
