import XCTest
@testable import NEARPrivateChat

extension PrivateChatCoreTests {
    func testMathFormulaModelParsesScriptsFractionsSymbolsAndFallbacks() {
        let scripts = MathFormulaRenderModel.build(from: "x^2 + y_i")
        guard case let .row(scriptNodes) = scripts else {
            return XCTFail("Expected script expression to parse as a row.")
        }
        XCTAssertEqual(scriptNodes.count, 5)
        XCTAssertEqual(
            scriptNodes[0],
            .superscript(base: .text("x", style: .math), exponent: .text("2", style: .math))
        )
        XCTAssertEqual(
            scriptNodes[4],
            .subscripted(base: .text("y", style: .math), lower: .text("i", style: .math))
        )
        XCTAssertTrue(scripts.isSimpleInline)
        XCTAssertNotNil(scripts.inlineAttributedString())

        let fraction = MathFormulaRenderModel.build(from: "\\frac{a+b}{2}")
        XCTAssertEqual(
            fraction,
            .fraction(numerator: .text("a+b", style: .math), denominator: .text("2", style: .math))
        )
        XCTAssertFalse(fraction.isSimpleInline)
        XCTAssertNil(fraction.inlineAttributedString())

        let symbols = MathFormulaRenderModel.build(from: "\\alpha \\leq \\beta")
        XCTAssertEqual(renderedFormulaText(symbols), "α ≤ β")
        XCTAssertTrue(symbols.isSimpleInline)

        let sqrtWithText = MathFormulaRenderModel.build(from: "\\sqrt{x} + \\text{units}")
        XCTAssertEqual(renderedFormulaText(sqrtWithText), "√x + units")

        let nested = MathFormulaRenderModel.build(from: "\\frac{1}{\\sqrt{x}}")
        guard case let .fraction(numerator, denominator) = nested else {
            return XCTFail("Expected nested expression to parse as a fraction.")
        }
        XCTAssertEqual(numerator, .text("1", style: .math))
        XCTAssertEqual(denominator, .squareRoot(.text("x", style: .math)))

        let unsupported = "\\begin{matrix}1&2\\\\3&4\\end{matrix}"
        XCTAssertEqual(MathFormulaRenderModel.build(from: unsupported), .fallback(unsupported))
    }

    private func renderedFormulaText(_ model: MathFormulaRenderModel) -> String {
        switch model {
        case let .row(nodes):
            return nodes.map(renderedFormulaText).joined()
        case let .text(value, _):
            return value
        case let .superscript(base, exponent):
            return renderedFormulaText(base) + renderedFormulaText(exponent)
        case let .subscripted(base, lower):
            return renderedFormulaText(base) + renderedFormulaText(lower)
        case let .fraction(numerator, denominator):
            return renderedFormulaText(numerator) + "/" + renderedFormulaText(denominator)
        case let .squareRoot(radicand):
            return "√" + renderedFormulaText(radicand)
        case let .fallback(source):
            return source
        }
    }
}
