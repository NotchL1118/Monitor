import Foundation

/// Matches the bundled Public Suffix List, including private hosting providers.
struct SiteDomain {
    static let shared: SiteDomain = {
        let url = Bundle.main.url(forResource: "public_suffix_list", withExtension: "dat")
            ?? Bundle.module.url(forResource: "public_suffix_list", withExtension: "dat")
        let source = url.flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? ""
        return SiteDomain(source: source)
    }()

    private let rules: Set<String>

    private init(source: String) {
        var rules = Set<String>()
        for line in source.split(whereSeparator: \.isNewline) {
            guard !line.hasPrefix("//"), let rule = line.split(whereSeparator: \.isWhitespace).first else { continue }
            if rule.utf8.allSatisfy({ $0 < 128 }) {
                rules.insert(String(rule))
            } else {
                let prefix = rule.hasPrefix("*.") ? "*." : (rule.hasPrefix("!") ? "!" : "")
                if let host = URL(string: "https://" + rule.dropFirst(prefix.count))?.host(percentEncoded: false) {
                    rules.insert(prefix + host)
                }
            }
        }
        self.rules = rules
    }

    func site(for host: String) -> String {
        let labels = host.lowercased().split(separator: ".")
        guard labels.count > 1, !rules.isEmpty, !host.contains(":"),
              !(labels.count == 4 && labels.allSatisfy({ UInt8($0) != nil })) else { return host }
        var suffixLength = 1
        for index in labels.indices {
            let suffix = labels[index...].joined(separator: ".")
            let length = labels.count - index
            if rules.contains("!" + suffix) { return suffix }
            if rules.contains(suffix) { suffixLength = max(suffixLength, length) }
            if index > 0 && rules.contains("*." + suffix) { suffixLength = max(suffixLength, length + 1) }
        }
        return labels.suffix(suffixLength + 1).joined(separator: ".")
    }
}
