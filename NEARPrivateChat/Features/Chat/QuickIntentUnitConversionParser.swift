import Foundation

extension QuickIntentParser {
    static func parseUnitConversion(_ text: String) -> (value: Double, from: String, to: String)? {
        let pattern = #"(-?\d[\d.,]*)\s*(°?[a-z]+)\s+(?:to|in|into|as)\s+(°?[a-z]+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else {
            return nil
        }
        func group(_ index: Int) -> String? {
            Range(match.range(at: index), in: text).map { String(text[$0]) }
        }
        guard let valueString = group(1)?.replacingOccurrences(of: ",", with: ""),
              let value = Double(valueString),
              let from = group(2), let to = group(3),
              UnitConverter.convert(value: value, from: from, to: to) != nil else {
            return nil
        }
        return (value, from, to)
    }

    /// Pulls the fact out of "remember that …" / "note that …" commands, keeping
    /// the original casing (names, etc.). `text` is lowercased, `original` the
    /// trimmed raw with the same prefix length.
}
