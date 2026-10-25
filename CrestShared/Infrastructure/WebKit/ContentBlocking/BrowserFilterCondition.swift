import Foundation

/// The boolean subset used by filter-list preprocessors; never evaluates code.
struct BrowserFilterCondition {
    // MARK: - Static Variables

    private static let enabled: Set<String> = [
        "env_safari", "env_mobile", "adguard_app_ios", "adguard_ext_safari", "cap_user_stylesheet",
    ]

    // MARK: - Variables

    private var tokens: [String]
    private var position = 0

    // MARK: - Actions - Parsing

    static func evaluate(_ expression: String) throws -> Bool {
        let regex = try NSRegularExpression(pattern: "&&|\\|\\||!|\\(|\\)|[A-Za-z_][A-Za-z_0-9]*")
        let range = NSRange(expression.startIndex..., in: expression)
        let tokens = regex.matches(in: expression, range: range).compactMap {
            Range($0.range, in: expression).map { String(expression[$0]) }
        }
        guard tokens.joined() == expression.filter({ !$0.isWhitespace }) else {
            throw BrowserFilterListError.invalidCondition
        }
        var parser = BrowserFilterCondition(tokens: tokens)
        let value = try parser.disjunction()
        guard parser.position == tokens.count else { throw BrowserFilterListError.invalidCondition }
        return value
    }

    private mutating func disjunction() throws -> Bool {
        var value = try conjunction()
        while consume("||") {
            let next = try conjunction()
            value = value || next
        }
        return value
    }

    private mutating func conjunction() throws -> Bool {
        var value = try atom()
        while consume("&&") {
            let next = try atom()
            value = value && next
        }
        return value
    }

    private mutating func atom() throws -> Bool {
        if consume("!") { return try !atom() }
        if consume("(") {
            let value = try disjunction()
            guard consume(")") else { throw BrowserFilterListError.invalidCondition }
            return value
        }
        guard position < tokens.count, tokens[position].first?.isLetter == true else {
            throw BrowserFilterListError.invalidCondition
        }
        defer { position += 1 }
        return Self.enabled.contains(tokens[position])
    }

    private mutating func consume(_ token: String) -> Bool {
        guard position < tokens.count, tokens[position] == token else { return false }
        position += 1
        return true
    }
}
