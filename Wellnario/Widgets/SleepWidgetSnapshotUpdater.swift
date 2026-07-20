import WidgetKit

@MainActor
enum SleepWidgetSnapshotUpdater {
    static func refresh(snapshot: AppleHealthSnapshot) {
        let calendar = Calendar.autoupdatingCurrent
        let overrideStore = SleepManualOverrideStore()
        let effectiveSnapshot = overrideStore.applying(to: snapshot, calendar: calendar)
        let today = LocalDay(containing: Date(), in: calendar.timeZone)
        let sleepDay = effectiveSnapshot.sleepTrend.last {
            LocalDay(containing: $0.date, in: calendar.timeZone) == today
        }
        let manualOverride = overrideStore.override(for: today)
        let detail = sleepDetail(
            snapshot: effectiveSnapshot,
            sleepDay: sleepDay,
            manualOverride: manualOverride
        )
        let configuration = overrideStore.qualityPreferences.configuration(
            dateOfBirthComponents: effectiveSnapshot.dateOfBirthComponents,
            calendar: calendar
        )
        let breakdown = sleepDay.flatMap {
            SleepQualityCalculator.breakdown(
                for: $0,
                in: effectiveSnapshot.sleepTrend,
                configuration: configuration,
                calendar: calendar
            )
        }

        let qualityScore = sleepDay?.qualityScore ?? breakdown?.totalScore
        let durationText = sleepDay?.hours.map {
            AppleHealthUIFormatting.compactDuration($0 * 3_600)
        } ?? "—"
        let regularityText = breakdown.map {
            "\($0.compliantDays)/\(SleepQualityCalculator.regularityWindowDays)"
        } ?? "—"
        let interruptionsText: String
        if let breakdown, sleepDay?.awakeHours != nil {
            interruptionsText = "\(AppleHealthUIFormatting.number(breakdown.awakePercentage, maximumFractionDigits: 0))%"
        } else {
            interruptionsText = "—"
        }

        SleepWidgetDataStore().save(
            SleepWidgetSnapshot(
                languageCode: LocalizationManager.shared.language.rawValue,
                detail: detail,
                qualityScore: qualityScore,
                qualityText: qualityScore.map { AppleHealthUIFormatting.number($0) } ?? "—",
                durationScore: breakdown?.durationScore,
                durationText: durationText,
                regularityScore: breakdown?.regularityScore,
                regularityText: regularityText,
                interruptionsScore: sleepDay?.awakeHours == nil ? nil : breakdown?.interruptionScore,
                interruptionsText: interruptionsText
            )
        )
        WidgetCenter.shared.reloadTimelines(ofKind: WellnarioSleepWidgetData.kind)
    }

    private static func sleepDetail(
        snapshot: AppleHealthSnapshot,
        sleepDay: AppleHealthSleepDay?,
        manualOverride: SleepManualOverride?
    ) -> String {
        let noData = L10n.text("wellness.no_data")
        if sleepDay?.hours != nil {
            if manualOverride != nil {
                return L10n.text("sleep.manual.source")
            }
            if let session = snapshot.latestSleepSession {
                return AppleHealthUIFormatting.sleepRange(session)
            }
            return noData
        }
        if let session = snapshot.latestSleepSession {
            if manualOverride != nil {
                return L10n.text("sleep.manual.source")
            }
            return AppleHealthUIFormatting.sleepRange(session)
        }
        return WellnessLocalStore.lastSleepFactor ?? noData
    }
}
