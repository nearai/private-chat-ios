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

    func testActionPrimarySupportsWhiteButtonTextContrast() {
        let ratio = Color.brandBlueToken.contrastRatioAgainstWhite()
        XCTAssertGreaterThanOrEqual(
            ratio,
            4.5,
            "actionPrimary/brandBlue must keep white CTA text at WCAG AA contrast."
        )
    }

    func testProductCodeUsesSemanticColorAliasesInsteadOfRawBrandBlue() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let appRoot = repoRoot.appendingPathComponent("NEARPrivateChat")
        let allowedFile = appRoot
            .appendingPathComponent("Core")
            .appendingPathComponent("DesignSystem")
            .appendingPathComponent("DesignTokens.swift")
            .standardizedFileURL
        var leaks: [String] = []

        guard let enumerator = FileManager.default.enumerator(
            at: appRoot,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            XCTFail("Unable to enumerate app sources.")
            return
        }

        for case let fileURL as URL in enumerator {
            guard fileURL.pathExtension == "swift",
                  fileURL.standardizedFileURL != allowedFile else {
                continue
            }
            let text = (try? String(contentsOf: fileURL, encoding: .utf8)) ?? ""
            if text.contains("Color.brandBlue") || text.contains(".brandBlue") {
                leaks.append(fileURL.path)
            }
        }

        XCTAssertTrue(
            leaks.isEmpty,
            "Use semantic aliases such as Color.brandAccent, Color.controlAccent, Color.routeCloud, or Color.sourceAccent outside DesignTokens.swift:\n\(leaks.joined(separator: "\n"))"
        )
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
