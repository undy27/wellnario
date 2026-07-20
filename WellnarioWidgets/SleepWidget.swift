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
                HStack(spacing: 4) {
                    SleepMetricRing(
                        title: copy.quality,
                        valueText: snapshot.qualityText,
                        score: snapshot.qualityScore,
                        gradient: [SleepWidgetPalette.violet, SleepWidgetPalette.fuchsia]
                    )
                    SleepMetricRing(
                        title: copy.duration,
                        valueText: snapshot.durationText,
                        score: snapshot.durationScore,
                        valueTextScale: 0.84,
                        gradient: [SleepWidgetPalette.cyan, SleepWidgetPalette.information]
                    )
                    SleepMetricRing(
                        title: copy.regularity,
                        valueText: snapshot.regularityText,
                        score: snapshot.regularityScore,
                        gradient: [SleepWidgetPalette.success, SleepWidgetPalette.cyan]
                    )
                    SleepMetricRing(
                        title: copy.interruptions,
                        valueText: snapshot.interruptionsText,
                        score: snapshot.interruptionsScore,
                        gradient: [SleepWidgetPalette.pink, SleepWidgetPalette.warning]
                    )
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

private struct SleepMetricRing: View {
    let title: String
    let valueText: String
    let score: Double?
    let valueTextScale: CGFloat
    let gradient: [Color]

    init(
        title: String,
        valueText: String,
        score: Double?,
        valueTextScale: CGFloat = 1,
        gradient: [Color]
    ) {
        self.title = title
        self.valueText = valueText
        self.score = score
        self.valueTextScale = valueTextScale
        self.gradient = gradient
    }

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.14), lineWidth: 7)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(
                        seamlessGradient,
                        style: StrokeStyle(lineWidth: 7, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))

                Text(valueText)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.60)
                    .lineLimit(1)
                    .scaleEffect(valueTextScale)
            }
            .frame(width: 64, height: 64)

            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.68))
                .multilineTextAlignment(.center)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity)
    }

    private var progress: CGFloat {
        CGFloat(min(max(score ?? 0, 0), 100) / 100)
    }

    private var seamlessGradient: AngularGradient {
        AngularGradient(
            colors: [gradient[0], gradient[1], gradient[0]],
            center: .center
        )
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
}
