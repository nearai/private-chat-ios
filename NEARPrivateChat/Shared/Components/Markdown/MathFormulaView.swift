import SwiftUI

indirect enum MathFormulaRenderModel: Equatable {
    case row([MathFormulaRenderModel])
    case text(String, style: MathFormulaTextStyle)
    case superscript(base: MathFormulaRenderModel, exponent: MathFormulaRenderModel)
    case subscripted(base: MathFormulaRenderModel, lower: MathFormulaRenderModel)
    case fraction(numerator: MathFormulaRenderModel, denominator: MathFormulaRenderModel)
    case squareRoot(MathFormulaRenderModel)
    case fallback(String)

    static func build(from source: String) -> MathFormulaRenderModel {
        var parser = MathFormulaModelParser(source: source)
        return parser.parse()
    }

    var isSimpleInline: Bool {
        switch self {
        case .fallback, .fraction, .squareRoot:
            return false
        case let .row(nodes):
            return !nodes.isEmpty && nodes.allSatisfy(\.isSimpleInline)
        case .text:
            return true
        case let .superscript(base, exponent):
            return base.isSimpleInline && exponent.isSimpleInline
        case let .subscripted(base, lower):
            return base.isSimpleInline && lower.isSimpleInline
        }
    }

    func inlineAttributedString() -> AttributedString? {
        guard isSimpleInline else { return nil }
        return attributedString(scale: 1, baselineOffset: 0)
    }

    private func attributedString(scale: CGFloat, baselineOffset: Double) -> AttributedString {
        switch self {
        case let .row(nodes):
            return nodes.reduce(into: AttributedString()) { output, node in
                output += node.attributedString(scale: scale, baselineOffset: baselineOffset)
            }
        case let .text(value, style):
            var output = AttributedString(value)
            output.font = style.font(scale: scale)
            output.baselineOffset = baselineOffset
            return output
        case let .superscript(base, exponent):
            var output = base.attributedString(scale: scale, baselineOffset: baselineOffset)
            output += exponent.attributedString(scale: scale * 0.72, baselineOffset: baselineOffset + 7)
            return output
        case let .subscripted(base, lower):
            var output = base.attributedString(scale: scale, baselineOffset: baselineOffset)
            output += lower.attributedString(scale: scale * 0.72, baselineOffset: baselineOffset - 4)
            return output
        case .fraction, .squareRoot, .fallback:
            return AttributedString()
        }
    }
}

enum MathFormulaTextStyle: Equatable {
    case math
    case upright

    func font(scale: CGFloat) -> Font {
        let textStyle: Font.TextStyle
        switch scale {
        case 0.95...:
            textStyle = .body
        case 0.72..<0.95:
            textStyle = .callout
        default:
            textStyle = .caption
        }

        switch self {
        case .math:
            return .system(textStyle, design: .serif).italic()
        case .upright:
            return .system(textStyle, design: .serif)
        }
    }
}

struct MathFormulaView: View {
    let formula: String

    private var model: MathFormulaRenderModel {
        MathFormulaRenderModel.build(from: formula)
    }

    var body: some View {
        MathFormulaNodeView(node: model, scale: 1)
            .fixedSize(horizontal: true, vertical: true)
            .padding(.vertical, 3)
    }
}

private struct MathFormulaNodeView: View {
    let node: MathFormulaRenderModel
    let scale: CGFloat

    var body: some View {
        switch node {
        case let .row(nodes):
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                ForEach(Array(nodes.enumerated()), id: \.offset) { _, node in
                    MathFormulaNodeView(node: node, scale: scale)
                }
            }
        case let .text(value, style):
            Text(value)
                .font(style.font(scale: scale))
        case let .superscript(base, exponent):
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                MathFormulaNodeView(node: base, scale: scale)
                MathFormulaNodeView(node: exponent, scale: scale * 0.72)
                    .baselineOffset(7 * scale)
            }
        case let .subscripted(base, lower):
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                MathFormulaNodeView(node: base, scale: scale)
                MathFormulaNodeView(node: lower, scale: scale * 0.72)
                    .baselineOffset(-4 * scale)
            }
        case let .fraction(numerator, denominator):
            VStack(spacing: 2) {
                MathFormulaNodeView(node: numerator, scale: scale * 0.84)
                    .padding(.horizontal, 3)
                Rectangle()
                    .fill(Color.primary.opacity(0.75))
                    .frame(height: 0.7)
                MathFormulaNodeView(node: denominator, scale: scale * 0.84)
                    .padding(.horizontal, 3)
            }
            .fixedSize()
        case let .squareRoot(radicand):
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text("√")
                    .font(.system(scale >= 0.95 ? .title3 : .body, design: .serif))
                VStack(spacing: 1) {
                    Rectangle()
                        .fill(Color.primary.opacity(0.75))
                        .frame(height: 0.7)
                    MathFormulaNodeView(node: radicand, scale: scale * 0.92)
                }
            }
            .fixedSize()
        case let .fallback(source):
            Text(source.isEmpty ? " " : source)
                .font(.system(.body, design: .serif).italic())
                .foregroundStyle(.primary)
                .fixedSize(horizontal: true, vertical: true)
        }
    }
}

private struct MathFormulaModelParser {
    private let source: String
    private var index: String.Index
    private var failed = false

    init(source: String) {
        self.source = source.trimmingCharacters(in: .whitespacesAndNewlines)
        self.index = self.source.startIndex
    }

    /// A single inline/block formula longer than this falls back to source
    /// rather than being parsed — bounds worst-case parse/render cost on
    /// adversarial model output.
    static let maxFormulaLength = 2_000
    /// Most scripts one atom can carry before we stop wrapping — guards
    /// against `x^x^x^…` building an unbounded render tree.
    private static let maxScriptChain = 8

    mutating func parse() -> MathFormulaRenderModel {
        guard !source.isEmpty else { return .fallback(source) }
        guard source.count <= Self.maxFormulaLength else { return .fallback(source) }
        let nodes = parseExpression(closing: nil, depth: 0)
        guard !failed, index == source.endIndex else {
            return .fallback(source)
        }
        return normalizedRow(nodes)
    }

    private mutating func parseExpression(closing: Character?, depth: Int) -> [MathFormulaRenderModel] {
        guard depth <= 3 else {
            failed = true
            return []
        }

        var nodes: [MathFormulaRenderModel] = []
        // `!failed` in the condition is load-bearing: a non-advancing failure
        // (e.g. a leading `^`/`_`) would otherwise spin forever on the same
        // character, hanging whichever thread renders the formula.
        while !failed, index < source.endIndex {
            if let closing, source[index] == closing {
                break
            }
            if source[index] == "}" {
                failed = true
                return nodes
            }

            var atom = parseAtom(depth: depth)
            var scriptCount = 0
            while !failed, index < source.endIndex, source[index] == "^" || source[index] == "_" {
                guard scriptCount < Self.maxScriptChain else {
                    failed = true
                    break
                }
                scriptCount += 1
                let marker = source[index]
                advance()
                let script = parseScriptArgument(depth: depth)
                if marker == "^" {
                    atom = .superscript(base: atom, exponent: script)
                } else {
                    atom = .subscripted(base: atom, lower: script)
                }
            }
            nodes.append(atom)
        }
        return coalesced(nodes)
    }

    private mutating func parseAtom(depth: Int) -> MathFormulaRenderModel {
        guard index < source.endIndex else {
            failed = true
            return .text("", style: .math)
        }

        if source[index].isWhitespace {
            consumeWhitespace()
            return .text(" ", style: .upright)
        }

        switch source[index] {
        case "\\":
            return parseCommand(depth: depth)
        case "{":
            return parseGroup(depth: depth)
        case "^", "_":
            // Consume the orphan marker so the caller's loop always advances,
            // even though we mark the parse as failed (→ source fallback).
            let marker = source[index]
            advance()
            failed = true
            return .text(String(marker), style: .math)
        default:
            return parsePlainRun()
        }
    }

    private mutating func parseCommand(depth: Int) -> MathFormulaRenderModel {
        advance()
        let nameStart = index
        while index < source.endIndex, source[index].isLetter {
            advance()
        }

        let name: String
        if nameStart == index, index < source.endIndex {
            name = String(source[index])
            advance()
        } else {
            name = String(source[nameStart..<index])
        }

        switch name {
        case "frac":
            let numerator = parseRequiredGroup(depth: depth + 1)
            let denominator = parseRequiredGroup(depth: depth + 1)
            return .fraction(numerator: numerator, denominator: denominator)
        case "sqrt":
            let radicand = parseRequiredGroup(depth: depth + 1)
            return .squareRoot(radicand)
        case "text":
            guard let text = parseRawGroupText() else {
                failed = true
                return .text("", style: .upright)
            }
            return .text(text, style: .upright)
        default:
            if let replacement = Self.symbols[name] {
                return .text(replacement, style: .math)
            }
            failed = true
            return .text("\\\(name)", style: .math)
        }
    }

    private mutating func parsePlainRun() -> MathFormulaRenderModel {
        let start = index
        while index < source.endIndex,
              !source[index].isWhitespace,
              !"\\{}^_".contains(source[index]) {
            advance()
        }
        return .text(String(source[start..<index]), style: .math)
    }

    private mutating func parseGroup(depth: Int) -> MathFormulaRenderModel {
        parseRequiredGroup(depth: depth + 1)
    }

    private mutating func parseRequiredGroup(depth: Int) -> MathFormulaRenderModel {
        guard index < source.endIndex, source[index] == "{" else {
            failed = true
            return .text("", style: .math)
        }
        advance()
        let nodes = parseExpression(closing: "}", depth: depth)
        guard index < source.endIndex, source[index] == "}" else {
            failed = true
            return .text("", style: .math)
        }
        advance()
        return normalizedRow(nodes)
    }

    private mutating func parseScriptArgument(depth: Int) -> MathFormulaRenderModel {
        guard index < source.endIndex else {
            failed = true
            return .text("", style: .math)
        }
        if source[index] == "{" {
            return parseRequiredGroup(depth: depth + 1)
        }
        return parseAtom(depth: depth + 1)
    }

    private mutating func parseRawGroupText() -> String? {
        guard index < source.endIndex, source[index] == "{" else { return nil }
        advance()
        let textStart = index
        var nestedDepth = 0
        while index < source.endIndex {
            if source[index] == "\\" {
                advance()
                if index < source.endIndex {
                    advance()
                }
                continue
            }
            if source[index] == "{" {
                nestedDepth += 1
                advance()
                continue
            }
            if source[index] == "}" {
                if nestedDepth == 0 {
                    let text = String(source[textStart..<index])
                    advance()
                    return text
                }
                nestedDepth -= 1
            }
            advance()
        }
        return nil
    }

    private mutating func consumeWhitespace() {
        while index < source.endIndex, source[index].isWhitespace {
            advance()
        }
    }

    private mutating func advance() {
        index = source.index(after: index)
    }

    private func normalizedRow(_ nodes: [MathFormulaRenderModel]) -> MathFormulaRenderModel {
        let normalized = coalesced(nodes).filter { node in
            if case let .text(value, _) = node {
                return !value.isEmpty
            }
            return true
        }
        if normalized.count == 1 {
            return normalized[0]
        }
        return .row(normalized)
    }

    private func coalesced(_ nodes: [MathFormulaRenderModel]) -> [MathFormulaRenderModel] {
        nodes.reduce(into: []) { output, node in
            if case let .text(next, nextStyle) = node,
               case let .text(existing, existingStyle) = output.last,
               nextStyle == existingStyle {
                output[output.count - 1] = .text(existing + next, style: existingStyle)
            } else {
                output.append(node)
            }
        }
    }

    private static let symbols: [String: String] = [
        "alpha": "α", "beta": "β", "gamma": "γ", "delta": "δ", "epsilon": "ε",
        "zeta": "ζ", "eta": "η", "theta": "θ", "iota": "ι", "kappa": "κ",
        "lambda": "λ", "mu": "μ", "nu": "ν", "xi": "ξ", "omicron": "ο",
        "pi": "π", "rho": "ρ", "sigma": "σ", "tau": "τ", "upsilon": "υ",
        "phi": "φ", "chi": "χ", "psi": "ψ", "omega": "ω",
        "Alpha": "Α", "Beta": "Β", "Gamma": "Γ", "Delta": "Δ", "Epsilon": "Ε",
        "Zeta": "Ζ", "Eta": "Η", "Theta": "Θ", "Iota": "Ι", "Kappa": "Κ",
        "Lambda": "Λ", "Mu": "Μ", "Nu": "Ν", "Xi": "Ξ", "Omicron": "Ο",
        "Pi": "Π", "Rho": "Ρ", "Sigma": "Σ", "Tau": "Τ", "Upsilon": "Υ",
        "Phi": "Φ", "Chi": "Χ", "Psi": "Ψ", "Omega": "Ω",
        "pm": "±", "times": "×", "cdot": "·", "leq": "≤", "geq": "≥",
        "neq": "≠", "approx": "≈", "infty": "∞", "sum": "∑", "prod": "∏",
        "int": "∫", "to": "→", "partial": "∂", "nabla": "∇"
    ]
}
