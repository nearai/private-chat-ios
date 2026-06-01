import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

extension Color {
    struct AccessibleRGB: Equatable {
        let red: Double
        let green: Double
        let blue: Double

        var color: Color {
            Color(red: red, green: green, blue: blue)
        }

        func contrastRatioAgainstWhite() -> Double {
            contrastRatio(against: AccessibleRGB(red: 1, green: 1, blue: 1))
        }

        func contrastRatio(against other: AccessibleRGB) -> Double {
            let ownLuminance = relativeLuminance
            let otherLuminance = other.relativeLuminance
            let lighter = max(ownLuminance, otherLuminance)
            let darker = min(ownLuminance, otherLuminance)
            return (lighter + 0.05) / (darker + 0.05)
        }

        private var relativeLuminance: Double {
            func channel(_ value: Double) -> Double {
                value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
            }
            return 0.2126 * channel(red) + 0.7152 * channel(green) + 0.0722 * channel(blue)
        }
    }

    static let appBackgroundLightToken = AccessibleRGB(red: 0.972, green: 0.974, blue: 0.966)
    static let appBackgroundDarkToken = AccessibleRGB(red: 0.055, green: 0.060, blue: 0.063)
    static let appSecondaryBackgroundDarkToken = AccessibleRGB(red: 0.098, green: 0.106, blue: 0.112)
    static let appPanelBackgroundDarkToken = AccessibleRGB(red: 0.075, green: 0.082, blue: 0.088)
    static let brandBlueToken = AccessibleRGB(red: 0.0, green: 0.427, blue: 0.749)
    static let proofVerifiedToken = AccessibleRGB(red: 0.0, green: 0.478, blue: 0.239)
    static let proofStaleToken = AccessibleRGB(red: 0.590, green: 0.390, blue: 0.0)

    static let brandBlack = Color(red: 0.0, green: 0.0, blue: 0.0)
    static let brandDarkGrey = Color(red: 0.153, green: 0.153, blue: 0.153)
    static let brandGrey = Color(red: 0.655, green: 0.655, blue: 0.655)
    static let brandOffWhite = Color(red: 0.933, green: 0.933, blue: 0.922)
    static let brandSky = Color(red: 0.514, green: 0.863, blue: 1.0)
    static let brandBlue = brandBlueToken.color
    static let appSelection = Color(red: 0.86, green: 0.94, blue: 1.0)
    static let appBlueTint = Color(red: 0.92, green: 0.97, blue: 1.0)
    static let appSymbolBlueBackground = Color(red: 0.78, green: 0.91, blue: 1.0)
    static let commandGradientMid = Color(red: 0.006, green: 0.16, blue: 0.28)
    static let commandGradientEnd = Color(red: 0.0, green: 0.38, blue: 0.72)
    static let googleBlue = Color(red: 0.259, green: 0.522, blue: 0.957)
    static let googleRed = Color(red: 0.918, green: 0.263, blue: 0.208)
    static let googleYellow = Color(red: 0.984, green: 0.737, blue: 0.024)
    static let googleGreen = Color(red: 0.204, green: 0.659, blue: 0.325)
    static let actionPrimary = Color.brandBlue
    static let primaryAction = Color.actionPrimary
    static let actionTint = Color.actionPrimary.opacity(0.12)
    static let actionPress = Color.actionPrimary.opacity(0.85)
    // Saturated avatar / chip fill — matches Claude Design --action-fill
    // (#C7E8FF light, rgba(0,145,253,0.22) dark).
    #if canImport(UIKit)
    static let actionFill = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.0, green: 0.569, blue: 0.992, alpha: 0.22)
            : UIColor(red: 0.78, green: 0.91, blue: 1.0, alpha: 1.0)
    })
    #else
    static let actionFill = Color(red: 0.78, green: 0.91, blue: 1.0)
    #endif
    static let proofVerified = proofVerifiedToken.color
    static let proofStale = proofStaleToken.color
    static let proofMismatch = Color(red: 0.898, green: 0.282, blue: 0.302)
    static let failedColor = Color.proofMismatch
    static let routeCloud = Color.textSecondary
    static let routePrivate = Color.proofVerified
    static let selectionSubtle = Color.appSelection
    static let intensitySurfaceBase = Color.appBackground
    static let intensityRowPlain = Color.clear
    static let intensityPanelSoft = Color.appPanelBackground
    static let intensityRowSelected = Color.selectionSubtle
    static let intensityCommandPrimary = Color.actionPrimary
    static let intensityProofArtifact = Color.proofVerified
    static let intensityDanger = Color.proofMismatch
    static let trustVerified = Color.proofVerified
    static let trustFreshAccent = Color.brandSky
    static let warningState = Color.proofStale
    static let destructiveState = Color.proofMismatch
    static let textPrimary = Color.primary

    #if canImport(UIKit)
    private static func dynamicColor(light: UIColor, dark: UIColor) -> Color {
        Color(UIColor { traits in
            traits.userInterfaceStyle == .dark ? dark : light
        })
    }

    static let appBackground = dynamicColor(
        light: UIColor(red: 0.972, green: 0.974, blue: 0.966, alpha: 1.0),
        dark: UIColor(red: 0.055, green: 0.060, blue: 0.063, alpha: 1.0)
    )
    static let appSecondaryBackground = dynamicColor(
        light: UIColor(red: 0.944, green: 0.949, blue: 0.944, alpha: 1.0),
        dark: UIColor(red: 0.098, green: 0.106, blue: 0.112, alpha: 1.0)
    )
    static let appPanelBackground = dynamicColor(
        light: .white,
        dark: UIColor(red: 0.075, green: 0.082, blue: 0.088, alpha: 1.0)
    )
    static let appBorder = dynamicColor(
        light: UIColor.black.withAlphaComponent(0.08),
        dark: UIColor.white.withAlphaComponent(0.11)
    )
    static let appHairline = dynamicColor(
        light: UIColor.black.withAlphaComponent(0.05),
        dark: UIColor.white.withAlphaComponent(0.07)
    )
    static let textSecondary = dynamicColor(
        light: UIColor(red: 0.153, green: 0.153, blue: 0.153, alpha: 0.72),
        dark: UIColor.white.withAlphaComponent(0.68)
    )
    static let textTertiary = dynamicColor(
        light: UIColor.black.withAlphaComponent(0.46),
        dark: UIColor.white.withAlphaComponent(0.46)
    )
    #elseif canImport(AppKit)
    static let appBackground = Color(red: 0.972, green: 0.974, blue: 0.966)
    static let appSecondaryBackground = Color(red: 0.944, green: 0.949, blue: 0.944)
    static let appPanelBackground = Color.white
    static let appBorder = Color.brandBlack.opacity(0.08)
    static let appHairline = Color.brandBlack.opacity(0.05)
    static let textSecondary = Color.brandDarkGrey.opacity(0.72)
    static let textTertiary = Color.brandBlack.opacity(0.46)
    #else
    static let appBackground = Color(red: 0.972, green: 0.974, blue: 0.966)
    static let appSecondaryBackground = Color(red: 0.944, green: 0.949, blue: 0.944)
    static let appPanelBackground = Color.white
    static let appBorder = Color.brandBlack.opacity(0.08)
    static let appHairline = Color.brandBlack.opacity(0.05)
    static let textSecondary = Color.brandDarkGrey.opacity(0.72)
    static let textTertiary = Color.brandBlack.opacity(0.46)
    #endif

    static let surface = Color.appBackground
    static let panel = Color.appPanelBackground
    static let secondarySurface = Color.appSecondaryBackground
    static let border = Color.appBorder
}
