import Foundation

enum SetupSoulPromptBuilder {
    static func markdown(for profile: UserSetupProfile) -> String {
        let useCases = profile.useCases.setupOrderedUnique
        var intentLines = useCases.map { "- \($0.title): \($0.subtitle)" }
        if profile.wantsWeb {
            intentLines.append("- Use current sources when freshness matters.")
        }
        if profile.wantsCouncil {
            intentLines.append("- Compare model perspectives when the answer benefits from a second pass.")
        }
        if profile.wantsIronclaw {
            intentLines.append("- Keep agent work concrete, bounded, and test-oriented.")
        }
        if intentLines.isEmpty {
            intentLines.append("- Private chat and practical answers.")
        }

        var ruleLines: [String] = []
        let goal = profile.normalizedGoalText
        if !goal.isEmpty {
            ruleLines.append("<important if=\"working on my setup goal\">Orient the answer around: \(goal)</important>")
        }
        if useCases.contains(.research) {
            ruleLines.append("<important if=\"researching\">Use dated sources and separate facts from inference.</important>")
        }
        if useCases.contains(.buildAgents) {
            ruleLines.append("<important if=\"planning agent work\">Prefer small, verifiable steps and name the next test.</important>")
        }

        let rulesSection = ruleLines.isEmpty ? "" : """

        ## Rules
        \(ruleLines.joined(separator: "\n"))
        """

        return """
        # soul.md

        ## Intent
        \(intentLines.joined(separator: "\n"))

        ## Voice & Format
        Lead with the answer. Keep responses concise and practical. Use bullets or checklists when they improve scanning.
        \(rulesSection)
        """
    }
}
