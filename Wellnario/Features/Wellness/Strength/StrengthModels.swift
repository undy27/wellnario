import Foundation

struct StrengthExercise: Identifiable, Hashable, Sendable {
    let id: String
    let nameEnglish: String
    let nameSpanish: String
    /// A personal label stored per user. It intentionally takes precedence in
    /// both languages: it is the name the user expects to find in their list.
    let customName: String?
    let force: String?
    let level: String?
    let mechanic: String?
    let equipment: String?
    let primaryMuscles: [String]
    let secondaryMuscles: [String]
    let instructionsEnglish: [String]
    let instructionsSpanish: [String]?
    let imagePaths: [String]

    init(
        id: String,
        nameEnglish: String,
        nameSpanish: String,
        customName: String? = nil,
        force: String?,
        level: String?,
        mechanic: String?,
        equipment: String?,
        primaryMuscles: [String],
        secondaryMuscles: [String],
        instructionsEnglish: [String],
        instructionsSpanish: [String]?,
        imagePaths: [String]
    ) {
        self.id = id
        self.nameEnglish = nameEnglish
        self.nameSpanish = nameSpanish
        self.customName = customName
        self.force = force
        self.level = level
        self.mechanic = mechanic
        self.equipment = equipment
        self.primaryMuscles = primaryMuscles
        self.secondaryMuscles = secondaryMuscles
        self.instructionsEnglish = instructionsEnglish
        self.instructionsSpanish = instructionsSpanish
        self.imagePaths = imagePaths
    }

    func localizedName(language: AppLanguage) -> String {
        if let customName, !customName.isEmpty { return customName }
        return language == .spanish ? nameSpanish : nameEnglish
    }

    func localizedInstructions(language: AppLanguage) -> [String] {
        guard language == .spanish, let instructionsSpanish, !instructionsSpanish.isEmpty else {
            return instructionsEnglish
        }
        return instructionsSpanish
    }
}

struct StrengthWorkoutSummary: Identifiable, Hashable, Sendable {
    let id: UUID
    let title: String
    let startedAt: Date
    let endedAt: Date?
    let exerciseCount: Int
    let totalVolume: Double
}

struct StrengthReportPoint: Identifiable, Hashable, Sendable {
    let id: String
    let label: String
    let value: Double
}

struct StrengthSessionVolume: Identifiable, Hashable, Sendable {
    let id: UUID
    let date: Date
    let volume: Double
}

struct StrengthReport: Hashable, Sendable {
    let sessionVolumes: [StrengthSessionVolume]
    let exerciseVolumes: [StrengthReportPoint]
    let averageSetVolume: Double
    let muscleVolumes: [StrengthReportPoint]
}

struct StrengthBodyMetric: Identifiable, Hashable, Sendable {
    let id: UUID
    var name: String
    var value: Decimal
    var unit: String?
    var measuredAt: Date
}

struct StrengthBodyMetricDraft: Sendable {
    var name: String
    var value: Decimal
    var unit: String?
    var measuredAt: Date

    init(name: String, value: Decimal, unit: String? = nil, measuredAt: Date) {
        self.name = name
        self.value = value
        self.unit = unit
        self.measuredAt = measuredAt
    }
}

struct StrengthWorkoutSet: Identifiable, Hashable, Sendable {
    let id: UUID
    var order: Int
    var weight: Decimal?
    var repetitions: Int?
    var restSeconds: Int?
    var isWarmup: Bool
    var isFailure: Bool
    var isDropSet: Bool
    var completedAt: Date?

    init(
        id: UUID = UUID(),
        order: Int,
        weight: Decimal? = nil,
        repetitions: Int? = nil,
        restSeconds: Int? = 90,
        isWarmup: Bool = false,
        isFailure: Bool = false,
        isDropSet: Bool = false,
        completedAt: Date? = nil
    ) {
        self.id = id
        self.order = order
        self.weight = weight
        self.repetitions = repetitions
        self.restSeconds = restSeconds
        self.isWarmup = isWarmup
        self.isFailure = isFailure
        self.isDropSet = isDropSet
        self.completedAt = completedAt
    }
}

struct StrengthWorkoutExercise: Identifiable, Hashable, Sendable {
    let id: UUID
    let exercise: StrengthExercise
    var order: Int
    var notes: String?
    var restSeconds: Int?
    var sets: [StrengthWorkoutSet]

    init(
        id: UUID = UUID(),
        exercise: StrengthExercise,
        order: Int,
        notes: String? = nil,
        restSeconds: Int? = nil,
        sets: [StrengthWorkoutSet] = [StrengthWorkoutSet(order: 1)]
    ) {
        self.id = id
        self.exercise = exercise
        self.order = order
        self.notes = notes
        let resolvedRestSeconds = restSeconds ?? sets.first?.restSeconds ?? 90
        self.restSeconds = resolvedRestSeconds
        self.sets = sets.map { set in
            var normalizedSet = set
            normalizedSet.restSeconds = resolvedRestSeconds
            return normalizedSet
        }
    }
}

struct StrengthPreviousSet: Hashable, Sendable {
    let weight: Decimal?
    let repetitions: Int?
}

struct StrengthWorkout: Identifiable, Hashable, Sendable {
    let id: UUID
    var title: String
    var startedAt: Date
    var endedAt: Date?
    var notes: String?
    var exercises: [StrengthWorkoutExercise]

    init(
        id: UUID = UUID(),
        title: String,
        startedAt: Date = Date(),
        endedAt: Date? = nil,
        notes: String? = nil,
        exercises: [StrengthWorkoutExercise] = []
    ) {
        self.id = id
        self.title = title
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.notes = notes
        self.exercises = exercises
    }
}

struct StrengthWorkoutTemplateExercise: Identifiable, Hashable, Sendable {
    let id: UUID
    let exercise: StrengthExercise
    var order: Int
    var defaultRestSeconds: Int?
    var sets: [StrengthWorkoutSet]
}

struct StrengthWorkoutTemplate: Identifiable, Hashable, Sendable {
    let id: UUID
    let nameKey: String?
    var name: String
    var notes: String?
    var exercises: [StrengthWorkoutTemplateExercise]
    let createdAt: Date
    var updatedAt: Date
}

struct StrengthWorkoutTemplateDraft: Sendable {
    var name: String
    var notes: String?
    var exercises: [StrengthWorkoutTemplateExercise]

    init(name: String, notes: String? = nil, exercises: [StrengthWorkoutTemplateExercise]) {
        self.name = name
        self.notes = notes
        self.exercises = exercises
    }
}
