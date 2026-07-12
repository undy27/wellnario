import Foundation

@MainActor
final class AppEnvironment {
    let repository: WellnarioRepositoryProtocol
    let launchConfiguration: AppLaunchConfiguration

    init(
        launchConfiguration: AppLaunchConfiguration = .current(),
        fileManager: FileManager = .default
    ) throws {
        self.launchConfiguration = launchConfiguration

        if let language = launchConfiguration.languageOverride {
            LocalizationManager.shared.setLanguage(language)
        }

        if launchConfiguration.isUITesting {
            let databaseURL = try Self.uiTestDatabaseURL(fileManager: fileManager)
            if launchConfiguration.resetsData {
                Self.removeSQLiteFiles(at: databaseURL, fileManager: fileManager)
            }
            repository = try WellnarioRepository(databaseURL: databaseURL)
        } else {
            repository = try WellnarioRepository.live(fileManager: fileManager)
        }
    }

    private static func uiTestDatabaseURL(fileManager: FileManager) throws -> URL {
        let directory = fileManager.temporaryDirectory
            .appendingPathComponent("WellnarioUITests", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("Wellnario.sqlite", isDirectory: false)
    }

    private static func removeSQLiteFiles(at databaseURL: URL, fileManager: FileManager) {
        let paths = [
            databaseURL.path,
            databaseURL.path + "-wal",
            databaseURL.path + "-shm"
        ]
        for path in paths where fileManager.fileExists(atPath: path) {
            try? fileManager.removeItem(atPath: path)
        }
    }
}
