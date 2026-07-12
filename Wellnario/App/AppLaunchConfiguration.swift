import Foundation

struct AppLaunchConfiguration: Sendable {
    enum InitialTab: Int, CaseIterable, Sendable {
        case today
        case supplements
        case diary
        case trends
        case more

        init?(argument: String) {
            switch argument.lowercased() {
            case "today", "hoy": self = .today
            case "supplements", "suplementos": self = .supplements
            case "diary", "diario": self = .diary
            case "trends", "tendencias": self = .trends
            case "more", "mas", "más": self = .more
            default: return nil
            }
        }
    }

    let isUITesting: Bool
    let resetsData: Bool
    let languageOverride: AppLanguage?
    let initialTab: InitialTab

    static func current(arguments: [String] = ProcessInfo.processInfo.arguments) -> AppLaunchConfiguration {
        let isUITesting = arguments.contains("--ui-testing")
        let resetsData = isUITesting && arguments.contains("--reset-data")
        let language = value(after: "--language", in: arguments).flatMap(AppLanguage.init(rawValue:))
        let initialTab = value(after: "--initial-tab", in: arguments)
            .flatMap(InitialTab.init(argument:)) ?? .today

        return AppLaunchConfiguration(
            isUITesting: isUITesting,
            resetsData: resetsData,
            languageOverride: language,
            initialTab: initialTab
        )
    }

    private static func value(after option: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: option) else { return nil }
        let valueIndex = arguments.index(after: index)
        guard arguments.indices.contains(valueIndex) else { return nil }
        return arguments[valueIndex]
    }
}
