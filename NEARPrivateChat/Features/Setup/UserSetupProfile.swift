import Foundation

struct UserSetupProfile: Codable, Hashable {
    var useCase: UserSetupUseCase {
        didSet {
            guard oldValue != useCase, !useCases.contains(useCase) else { return }
            useCases = [useCase]
        }
    }
    var useCases: [UserSetupUseCase]
    var goalText: String
    var contextStyle: UserSetupContextStyle
    var wantsWeb: Bool
    var wantsIronclaw: Bool
    var wantsCouncil: Bool
    var experienceMode: UserSetupExperienceMode
    var routeDefaults: SetupRouteDefaults

    init(
        useCase: UserSetupUseCase,
        contextStyle: UserSetupContextStyle,
        wantsWeb: Bool,
        wantsIronclaw: Bool,
        wantsCouncil: Bool,
        useCases: [UserSetupUseCase]? = nil,
        goalText: String = "",
        experienceMode: UserSetupExperienceMode = .beginner,
        routeDefaults: SetupRouteDefaults = .empty
    ) {
        let normalizedUseCases = (useCases ?? [useCase]).setupOrderedUnique
        self.useCases = normalizedUseCases
        self.useCase = normalizedUseCases.setupPrimaryUseCase
        self.goalText = String(goalText.trimmingCharacters(in: .whitespacesAndNewlines).prefix(280))
        self.contextStyle = contextStyle
        self.wantsWeb = wantsWeb
        self.wantsIronclaw = wantsIronclaw
        self.wantsCouncil = wantsCouncil
        self.experienceMode = experienceMode
        self.routeDefaults = routeDefaults.normalized
    }

    enum CodingKeys: String, CodingKey {
        case useCase
        case useCases
        case goalText
        case contextStyle
        case wantsWeb
        case wantsIronclaw
        case wantsCouncil
        case experienceMode
        case routeDefaults
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let storedUseCase = try container.decodeIfPresent(UserSetupUseCase.self, forKey: .useCase) ?? .privateChat
        let storedUseCases = try container.decodeIfPresent([UserSetupUseCase].self, forKey: .useCases)
        let normalizedUseCases = (storedUseCases ?? [storedUseCase]).setupOrderedUnique
        useCases = normalizedUseCases
        useCase = normalizedUseCases.setupPrimaryUseCase
        goalText = try container.decodeIfPresent(String.self, forKey: .goalText) ?? ""
        contextStyle = try container.decodeIfPresent(UserSetupContextStyle.self, forKey: .contextStyle) ?? .simple
        wantsWeb = try container.decodeIfPresent(Bool.self, forKey: .wantsWeb) ?? false
        wantsIronclaw = try container.decodeIfPresent(Bool.self, forKey: .wantsIronclaw) ?? false
        wantsCouncil = try container.decodeIfPresent(Bool.self, forKey: .wantsCouncil) ?? false
        experienceMode = try container.decodeIfPresent(UserSetupExperienceMode.self, forKey: .experienceMode) ?? .beginner
        routeDefaults = (try container.decodeIfPresent(SetupRouteDefaults.self, forKey: .routeDefaults) ?? .empty).normalized
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(useCase, forKey: .useCase)
        try container.encode(useCases.setupOrderedUnique, forKey: .useCases)
        try container.encode(goalText, forKey: .goalText)
        try container.encode(contextStyle, forKey: .contextStyle)
        try container.encode(wantsWeb, forKey: .wantsWeb)
        try container.encode(wantsIronclaw, forKey: .wantsIronclaw)
        try container.encode(wantsCouncil, forKey: .wantsCouncil)
        try container.encode(experienceMode, forKey: .experienceMode)
        try container.encode(routeDefaults.normalized, forKey: .routeDefaults)
    }

    var normalizedForDefaults: UserSetupProfile {
        var profile = self
        profile.useCases = useCases.setupOrderedUnique
        profile.useCase = profile.useCases.setupPrimaryUseCase
        profile.goalText = normalizedGoalText
        profile.routeDefaults = routeDefaults.normalized
        return profile
    }

    var normalizedGoalText: String {
        String(goalText.trimmingCharacters(in: .whitespacesAndNewlines).prefix(280))
    }
}
