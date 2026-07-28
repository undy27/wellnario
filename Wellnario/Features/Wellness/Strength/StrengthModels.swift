import Foundation

struct StrengthExercise: Identifiable, Hashable, Sendable {
    let id: String
    let nameEnglish: String
    let nameSpanish: String
    let force: String?
    let level: String?
    let mechanic: String?
    let equipment: String?
    let primaryMuscles: [String]
    let secondaryMuscles: [String]
    let instructionsEnglish: [String]
    let instructionsSpanish: [String]?
    let imagePaths: [String]

    func localizedName(language: AppLanguage) -> String {
        language == .spanish ? nameSpanish : nameEnglish
    }

    func localizedInstructions(language: AppLanguage) -> [String] {
        guard language == .spanish, let instructionsSpanish, !instructionsSpanish.isEmpty else {
            return instructionsEnglish
        }
        return instructionsSpanish
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
    var sets: [StrengthWorkoutSet]

    init(
        id: UUID = UUID(),
        exercise: StrengthExercise,
        order: Int,
        notes: String? = nil,
        sets: [StrengthWorkoutSet] = [StrengthWorkoutSet(order: 1)]
    ) {
        self.id = id
        self.exercise = exercise
        self.order = order
        self.notes = notes
        self.sets = sets
    }
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
