import Foundation

/// On-device arithmetic evaluator. Hand-rolled tokenizer + recursive-descent
/// parser (NOT NSExpression(format:), which throws uncatchable ObjC exceptions
/// on malformed input). Pure, deterministic, crash-proof: any unparseable input
/// returns nil. Handles + - * / and parentheses, spelled operators ("plus",
/// "times", "divided by"), ×/÷/x, and percentages ("18% of 85", "50%").
enum MathEvaluator {
    static func evaluate(_ raw: String) -> Double? {
        var s = raw.lowercased()
        s = s.replacingOccurrences(of: ",", with: "")            // 1,000 → 1000
        s = s.replacingOccurrences(of: "multiplied by", with: "*")
        s = s.replacingOccurrences(of: "divided by", with: "/")
        s = s.replacingOccurrences(of: "divide by", with: "/")
        s = s.replacingOccurrences(of: "plus", with: "+")
        s = s.replacingOccurrences(of: "minus", with: "-")
        s = s.replacingOccurrences(of: "times", with: "*")
        s = s.replacingOccurrences(of: "÷", with: "/")
        s = s.replacingOccurrences(of: "×", with: "*")
        // "x" as multiply, only between numbers/parens (so it can't eat words).
        s = s.replacingOccurrences(of: #"(?<=[0-9).])\s*x\s*(?=[0-9(.])"#, with: "*", options: .regularExpression)
        // "18% of 85" → "(18*0.01)*85"; then a standalone "50%" → "(50*0.01)".
        s = s.replacingOccurrences(of: #"([0-9.]+)\s*%\s*of\s+"#, with: "($1*0.01)*", options: .regularExpression)
        s = s.replacingOccurrences(of: #"([0-9.]+)\s*%"#, with: "($1*0.01)", options: .regularExpression)

        guard let tokens = tokenize(s) else { return nil }
        var parser = RecursiveParser(tokens: tokens)
        guard let value = parser.parseExpression(), parser.isAtEnd, value.isFinite else { return nil }
        return value
    }

    /// "84" for integers, trimmed decimals otherwise ("15.39", "0.6667").
    static func format(_ value: Double) -> String {
        guard value.isFinite else { return "" }
        if value == value.rounded(), abs(value) < 1e15 {
            return String(Int(value))
        }
        var s = String(format: "%.4f", value)
        while s.hasSuffix("0") { s.removeLast() }
        if s.hasSuffix(".") { s.removeLast() }
        return s
    }

    private enum Token: Equatable { case number(Double), plus, minus, mul, div, lParen, rParen }

    private static func tokenize(_ s: String) -> [Token]? {
        var tokens: [Token] = []
        let chars = Array(s)
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if c == " " { i += 1; continue }
            switch c {
            case "+": tokens.append(.plus); i += 1
            case "-": tokens.append(.minus); i += 1
            case "*": tokens.append(.mul); i += 1
            case "/": tokens.append(.div); i += 1
            case "(": tokens.append(.lParen); i += 1
            case ")": tokens.append(.rParen); i += 1
            case "0"..."9", ".":
                var num = ""
                while i < chars.count, chars[i].isNumber || chars[i] == "." {
                    num.append(chars[i]); i += 1
                }
                guard let value = Double(num) else { return nil }
                tokens.append(.number(value))
            default:
                return nil // any non-math character rejects the whole input
            }
        }
        return tokens
    }

    /// expr := term (('+'|'-') term)*; term := factor (('*'|'/') factor)*;
    /// factor := number | '(' expr ')' | ('-'|'+') factor
    private struct RecursiveParser {
        let tokens: [Token]
        var index = 0
        var isAtEnd: Bool { index >= tokens.count }
        private func peek() -> Token? { index < tokens.count ? tokens[index] : nil }
        private mutating func advance() -> Token? { defer { index += 1 }; return peek() }

        mutating func parseExpression() -> Double? {
            guard var value = parseTerm() else { return nil }
            while let op = peek(), op == .plus || op == .minus {
                index += 1
                guard let rhs = parseTerm() else { return nil }
                value = (op == .plus) ? value + rhs : value - rhs
            }
            return value
        }

        private mutating func parseTerm() -> Double? {
            guard var value = parseFactor() else { return nil }
            while let op = peek(), op == .mul || op == .div {
                index += 1
                guard let rhs = parseFactor() else { return nil }
                value = (op == .mul) ? value * rhs : value / rhs
            }
            return value
        }

        private mutating func parseFactor() -> Double? {
            switch peek() {
            case .minus: index += 1; return parseFactor().map { -$0 }
            case .plus: index += 1; return parseFactor()
            case let .number(value): index += 1; return value
            case .lParen:
                index += 1
                guard let value = parseExpression(), peek() == .rParen else { return nil }
                index += 1
                return value
            default:
                return nil
            }
        }
    }
}

/// On-device date arithmetic — whole-day counts, future dates, and the next
/// occurrence of a fixed-date holiday. Pure + deterministic (every function
/// takes `now`), so it's fully unit-testable.
enum DateMath {
    /// Whole-day count from today to the target day (negative if already past).
    static func daysUntil(_ target: Date, now: Date) -> Int {
        let cal = Calendar.current
        return cal.dateComponents([.day], from: cal.startOfDay(for: now), to: cal.startOfDay(for: target)).day ?? 0
    }

    static func adding(_ value: Int, _ unit: Calendar.Component, to now: Date) -> Date? {
        Calendar.current.date(byAdding: unit, value: value, to: now)
    }

    /// "Friday, December 25, 2026"
    static func longDate(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.wide).month(.wide).day().year())
    }

    /// The next occurrence (today or later) of a fixed month/day.
    static func nextOccurrence(month: Int, day: Int, now: Date) -> Date? {
        let cal = Calendar.current
        let year = cal.component(.year, from: now)
        var components = DateComponents()
        components.month = month
        components.day = day
        for candidateYear in [year, year + 1] {
            components.year = candidateYear
            if let date = cal.date(from: components),
               cal.startOfDay(for: date) >= cal.startOfDay(for: now) {
                return date
            }
        }
        return nil
    }

    /// Fixed-date holidays we can resolve by name (no movable feasts).
    static let holidays: [(names: [String], month: Int, day: Int)] = [
        (["new year's eve", "new years eve"], 12, 31),
        (["christmas eve"], 12, 24),
        (["christmas", "xmas"], 12, 25),
        (["new year", "new years", "new year's"], 1, 1),
        (["valentine's day", "valentines day", "valentine's", "valentines", "valentine"], 2, 14),
        (["halloween"], 10, 31),
        (["independence day", "fourth of july", "4th of july", "july 4th"], 7, 4),
    ]
}

/// On-device unit conversion (length / mass / temperature). Linear units carry
/// a factor to a base unit; temperature is handled by formula.
enum UnitConverter {
    private struct LinearUnit { let symbol: String; let category: String; let toBase: Double }

    private static let linear: [String: LinearUnit] = {
        var map: [String: LinearUnit] = [:]
        func add(_ aliases: [String], _ symbol: String, _ category: String, _ toBase: Double) {
            for alias in aliases { map[alias] = LinearUnit(symbol: symbol, category: category, toBase: toBase) }
        }
        // length (base: meter)
        add(["m", "meter", "meters", "metre", "metres"], "m", "length", 1)
        add(["km", "kilometer", "kilometers", "kilometre", "kilometres"], "km", "length", 1000)
        add(["cm", "centimeter", "centimeters"], "cm", "length", 0.01)
        add(["mm", "millimeter", "millimeters"], "mm", "length", 0.001)
        add(["mi", "mile", "miles"], "mi", "length", 1609.344)
        add(["ft", "foot", "feet"], "ft", "length", 0.3048)
        add(["yd", "yard", "yards"], "yd", "length", 0.9144)
        add(["in", "inch", "inches"], "in", "length", 0.0254)
        // mass (base: gram)
        add(["g", "gram", "grams"], "g", "mass", 1)
        add(["kg", "kilogram", "kilograms", "kilo", "kilos"], "kg", "mass", 1000)
        add(["mg", "milligram", "milligrams"], "mg", "mass", 0.001)
        add(["lb", "lbs", "pound", "pounds"], "lb", "mass", 453.59237)
        add(["oz", "ounce", "ounces"], "oz", "mass", 28.349523)
        add(["ton", "tonne", "tonnes", "tons"], "t", "mass", 1_000_000)
        return map
    }()

    private static func canonicalTemp(_ raw: String) -> String? {
        switch raw.replacingOccurrences(of: "°", with: "") {
        case "c", "celsius", "centigrade": return "°C"
        case "f", "fahrenheit": return "°F"
        case "k", "kelvin": return "K"
        default: return nil
        }
    }

    static func convert(value: Double, from: String, to: String) -> (result: Double, fromSymbol: String, toSymbol: String)? {
        let f = from.lowercased(), t = to.lowercased()
        if let cf = canonicalTemp(f), let ct = canonicalTemp(t) {
            return (convertTemperature(value, from: cf, to: ct), cf, ct)
        }
        let key = { (s: String) in s.replacingOccurrences(of: "°", with: "") }
        guard let fu = linear[key(f)], let tu = linear[key(t)], fu.category == tu.category else { return nil }
        return (value * fu.toBase / tu.toBase, fu.symbol, tu.symbol)
    }

    private static func convertTemperature(_ value: Double, from: String, to: String) -> Double {
        let celsius: Double
        switch from {
        case "°F": celsius = (value - 32) * 5 / 9
        case "K": celsius = value - 273.15
        default: celsius = value
        }
        switch to {
        case "°F": return celsius * 9 / 5 + 32
        case "K": return celsius + 273.15
        default: return celsius
        }
    }
}
