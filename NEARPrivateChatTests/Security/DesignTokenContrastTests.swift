import XCTest
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif
@testable import NEARPrivateChat

extension PrivateChatCoreTests {
    func testDesignTextTokensMeetWCAGAAOnLightBackground() throws {
        #if canImport(UIKit)
        let background = try resolvedRGBA(from: Color.appBackground)
        let tokens: [(name: String, color: Color)] = [
            ("actionPrimaryText", .actionPrimaryText),
            ("proofVerifiedText", .proofVerifiedText),
            ("proofStaleText", .proofStaleText)
        ]

        for token in tokens {
            let foreground = try resolvedRGBA(from: token.color)
            XCTAssertGreaterThanOrEqual(
                contrastRatio(foreground, background),
                4.5,
                "\(token.name) must meet WCAG AA contrast against appBackground in light mode."
            )
        }
        #else
        throw XCTSkip("UIKit color resolution is unavailable on this platform.")
        #endif
    }

    func testDesignRadiusAndSpacingTokensExposeExpectedValues() {
        XCTAssertEqual(AppRadius.pill, CGFloat(8))
        XCTAssertEqual(AppRadius.control, CGFloat(12))
        XCTAssertEqual(AppRadius.card, CGFloat(16))
        XCTAssertEqual(AppRadius.sheet, CGFloat(22))

        XCTAssertEqual(AppSpacing.xs, CGFloat(4))
        XCTAssertEqual(AppSpacing.sm, CGFloat(8))
        XCTAssertEqual(AppSpacing.md, CGFloat(12))
        XCTAssertEqual(AppSpacing.lg, CGFloat(16))
        XCTAssertEqual(AppSpacing.xl, CGFloat(20))
        XCTAssertEqual(AppSpacing.xxl, CGFloat(24))
        XCTAssertEqual(AppSpacing.xxxl, CGFloat(32))
    }

    #if canImport(UIKit)
    private func resolvedRGBA(from color: Color) throws -> (red: Double, green: Double, blue: Double) {
        let traits = UITraitCollection(userInterfaceStyle: .light)
        let resolved = UIColor(color).resolvedColor(with: traits)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0

        guard resolved.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else {
            throw XCTSkip("Unable to resolve color into sRGB components.")
        }

        return (Double(red), Double(green), Double(blue))
    }

    private func contrastRatio(
        _ lhs: (red: Double, green: Double, blue: Double),
        _ rhs: (red: Double, green: Double, blue: Double)
    ) -> Double {
        let lhsLuminance = relativeLuminance(lhs)
        let rhsLuminance = relativeLuminance(rhs)
        let lighter = max(lhsLuminance, rhsLuminance)
        let darker = min(lhsLuminance, rhsLuminance)
        return (lighter + 0.05) / (darker + 0.05)
    }

    private func relativeLuminance(_ color: (red: Double, green: Double, blue: Double)) -> Double {
        func channel(_ value: Double) -> Double {
            value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }

        return 0.2126 * channel(color.red)
            + 0.7152 * channel(color.green)
            + 0.0722 * channel(color.blue)
    }
    #endif
}
