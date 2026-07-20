import AppIntents

/// The action exposed to Shortcuts. It deliberately performs only a read-only
/// HealthKit refresh, then publishes the updated sleep snapshot to WidgetKit.
struct SyncAppleHealthIntent: AppIntent {
    static let title: LocalizedStringResource = "Sincronizar Apple Health"
    static let description = IntentDescription(
        "Actualiza los datos de Apple Health y los widgets de Wellnario."
    )
    static let openAppWhenRun = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        switch await AppleHealthShortcutSyncRunner.sync() {
        case .completed:
            return .result(dialog: "Apple Health y los widgets se han actualizado.")
        case .notConfigured:
            return .result(dialog: "Conecta Apple Health en Wellnario antes de usar este atajo.")
        case .failed:
            return .result(dialog: "No se ha podido sincronizar Apple Health. Revisa los permisos e inténtalo de nuevo.")
        }
    }
}

struct WellnarioAppShortcuts: AppShortcutsProvider {
    static let shortcutTileColor: ShortcutTileColor = .blue

    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: SyncAppleHealthIntent(),
            phrases: [
                "Sincronizar Apple Health con \(.applicationName)",
                "Actualizar mis datos de salud con \(.applicationName)"
            ],
            shortTitle: "Sincronizar Apple Health",
            systemImageName: "arrow.triangle.2.circlepath.heart.fill"
        )
    }
}

private enum AppleHealthShortcutSyncOutcome: Sendable {
    case completed
    case notConfigured
    case failed
}

@MainActor
private enum AppleHealthShortcutSyncRunner {
    static func sync() async -> AppleHealthShortcutSyncOutcome {
        let service = AppleHealthSyncService()
        guard service.isConfigured else { return .notConfigured }

        do {
            try await service.sync()
            SleepWidgetSnapshotUpdater.refresh(snapshot: service.snapshot)
            return .completed
        } catch {
            return .failed
        }
    }
}
