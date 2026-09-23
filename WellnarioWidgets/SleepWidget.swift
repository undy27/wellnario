import SwiftUI
import WidgetKit

struct SleepWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: SleepWidgetSnapshot
}

struct SleepWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> SleepWidgetEntry {
        SleepWidgetEntry(date: Date(), snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (SleepWidgetEntry) -> Void) {
        completion(currentEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SleepWidgetEntry>) -> Void) {
        completion(Timeline(entries: [currentEntry()], policy: .never))
    }

    private func currentEntry() -> SleepWidgetEntry {
        SleepWidgetEntry(
            date: Date(),
            snapshot: SleepWidgetDataStore().snapshot() ?? .placeholder
        )
    }
}

struct SleepSummaryWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: WellnarioSleepWidgetData.kind,
            provider: SleepWidgetProvider()
        ) { entry in
            SleepWidgetView(snapshot: entry.snapshot)
        }
        .configurationDisplayName("Sueño")
        .description("Consulta la tarjeta de sueño de Hoy.")
        .supportedFamilies([.systemMedium])
        .contentMarginsDisabled()
    }
}

private struct SleepWidgetView: View {
    let snapshot: SleepWidgetSnapshot

    private var copy: SleepWidgetCopy {
        SleepWidgetCopy(languageCode: snapshot.languageCode)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            header
            Link(destination: SupplementWidgetURL.sleepWidget) {
                HStack(spacing: 10) {
                    SleepQualityRing(
                        title: copy.quality,
                        valueText: snapshot.qualityText,
                        score: snapshot.qualityScore
                    )
                    VStack(spacing: 2) {
                        SleepFactorRow(
                            title: copy.duration,
                            valueText: snapshot.durationText,
                            score: snapshot.durationScore,
                            symbolName: "bed.double.fill"
                        )
                        SleepFactorRow(
                            title: copy.regularity,
                            valueText: snapshot.regularityText,
                            score: snapshot.regularityScore,
                            symbolName: "calendar"
                        )
                        SleepFactorRow(
                            title: copy.interruptions,
                            valueText: snapshot.interruptionsText,
                            score: snapshot.interruptionsScore,
                            symbolName: "moon.zzz.fill"
                        )
                        SleepFactorRow(
                            title: copy.heartRateDrop,
                            valueText: snapshot.heartRateDropText ?? "—",
                            score: snapshot.heartRateDropScore,
                            symbolName: "heart.fill"
                        )
                        SleepFactorRow(
                            title: copy.sleepStress,
                            valueText: snapshot.sleepStressText ?? "—",
                            score: snapshot.sleepStressScore,
                            symbolName: "waveform.path.ecg"
                        )
                        SleepFactorRow(
                            title: copy.remDeepSleep,
                            valueText: snapshot.remDeepSleepText ?? "—",
                            score: snapshot.remDeepSleepScore,
                            symbolName: "brain.head.profile"
                        )
                        SleepFactorRow(
                            title: copy.sleepLatency,
                            valueText: snapshot.sleepLatencyText ?? "—",
                            score: snapshot.sleepLatencyScore,
                            symbolName: "hourglass"
                        )
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .containerBackground(for: .widget) {
            LinearGradient(
                colors: [SleepWidgetPalette.surfaceTop, SleepWidgetPalette.surfaceBottom],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }

    private var header: some View {
        HStack(spacing: 7) {
            Link(destination: SupplementWidgetURL.sleepWidget) {
                HStack(spacing: 7) {
                    Image(systemName: "moon.stars.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(SleepWidgetPalette.violet)
                        .frame(width: 36, height: 36)
                        .background(
                            SleepWidgetPalette.violet.opacity(0.14),
                            in: RoundedRectangle(cornerRadius: 11, style: .continuous)
                        )

                    Text(copy.title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    Spacer(minLength: 0)

                    Text(snapshot.detail)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.68))
                        .lineLimit(1)
                        .minimumScaleFactor(0.70)
                }
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .leading)

        }
    }
}

private struct SleepQualityRing: View {
    let title: String
    let valueText: String
    let score: Double?

    var body: some View {
        VStack(spacing: 3) {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.14), lineWidth: 6)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(
                        seamlessGradient,
                        style: StrokeStyle(lineWidth: 6, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))

                Text(valueText)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.60)
                    .lineLimit(1)
            }
            .frame(width: 68, height: 68)

            Text(title)
            .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.68))
                .multilineTextAlignment(.center)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity)
        }
        .frame(width: 68)
    }

    private var progress: CGFloat {
        CGFloat(min(max(score ?? 0, 0), 100) / 100)
    }

    private var seamlessGradient: AngularGradient {
        AngularGradient(
            colors: [
                SleepWidgetPalette.violet,
                SleepWidgetPalette.fuchsia,
                SleepWidgetPalette.violet
            ],
            center: .center
        )
    }
}

private struct SleepFactorRow: View {
    let title: String
    let valueText: String
    let score: Double?
    let symbolName: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: symbolName)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(SleepWidgetPalette.violet)
                .frame(width: 15)

            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.68))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .frame(width: 78, alignment: .leading)

            SleepFactorSegmentBar(score: score)
                .frame(maxWidth: .infinity)
                .frame(height: 7)

            Text(valueText)
                .font(.system(size: 11, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.68)
                .frame(width: 36, alignment: .trailing)
        }
        .frame(height: 12)
    }
}

private struct SleepFactorSegmentBar: View {
    private static let segmentCount = 10

    let score: Double?

    var body: some View {
        GeometryReader { proxy in
            HStack(spacing: 1.5) {
                ForEach(0..<Self.segmentCount, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                        .fill(index < activeSegmentCount ? activeColor(for: index) : Color.white.opacity(0.14))
                        .frame(
                            width: max(
                                (proxy.size.width - CGFloat(Self.segmentCount - 1) * 1.5)
                                    / CGFloat(Self.segmentCount),
                                0
                            )
                        )
                }
            }
        }
    }

    private var activeSegmentCount: Int {
        guard let score else { return 0 }
        let normalized = min(max(score / 100, 0), 1)
        return Int((normalized * Double(Self.segmentCount)).rounded(.up))
    }

    private func activeColor(for index: Int) -> Color {
        let progress = Double(index) / Double(max(Self.segmentCount - 1, 1))
        if progress < 0.4 { return SleepWidgetPalette.danger }
        if progress < 0.7 { return SleepWidgetPalette.warning }
        return SleepWidgetPalette.success
    }
}

private struct SleepWidgetCopy {
    let languageCode: String

    private var isEnglish: Bool { languageCode.lowercased().hasPrefix("en") }

    var title: String { isEnglish ? "Sleep" : "Sueño" }
    var quality: String { isEnglish ? "Quality" : "Calidad" }
    var duration: String { isEnglish ? "Duration" : "Duración" }
    var regularity: String { isEnglish ? "Regularity" : "Regularidad" }
    var interruptions: String { isEnglish ? "Interruptions" : "Interrupciones" }
    var heartRateDrop: String { isEnglish ? "HR drop" : "Caída FC" }
    var sleepStress: String { isEnglish ? "Stress" : "Estrés" }
    var remDeepSleep: String { isEnglish ? "REM + deep" : "REM + profundo" }
    var sleepLatency: String { isEnglish ? "Latency" : "Latencia" }
}

private enum SleepWidgetPalette {
    static let surfaceTop = Color(red: 0.125, green: 0.125, blue: 0.145)
    static let surfaceBottom = Color(red: 0.098, green: 0.098, blue: 0.114)
    static let violet = Color(red: 0.502, green: 0.424, blue: 1.00)
    static let fuchsia = Color(red: 0.851, green: 0.306, blue: 0.925)
    static let cyan = Color(red: 0.251, green: 0.863, blue: 0.902)
    static let information = Color(red: 0.357, green: 0.655, blue: 1.00)
    static let success = Color(red: 0.400, green: 0.886, blue: 0.435)
    static let pink = Color(red: 1.00, green: 0.243, blue: 0.490)
    static let warning = Color(red: 1.00, green: 0.706, blue: 0.302)
    static let danger = Color(red: 1.00, green: 0.306, blue: 0.306)
}
