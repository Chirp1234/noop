#if os(iOS)
import Foundation

// Value types for the Fit tab (workout planner/logger + food & calorie tracker). Everything is
// stored on-device in one JSON file by `FitStore`; nothing here touches the strap database.

enum FitExerciseKind: String, Codable, CaseIterable {
    /// load × reps
    case weight
    /// seconds held, optional added load
    case time
    /// distance (km) + minutes
    case cardio
}

enum FitMuscle: String, Codable, CaseIterable, Identifiable {
    case chest, back, shoulders, biceps, triceps, legs, abs, cardio

    var id: String { rawValue }

    var label: String {
        switch self {
        case .chest: return "Chest"
        case .back: return "Back"
        case .shoulders: return "Shoulders"
        case .biceps: return "Biceps"
        case .triceps: return "Triceps"
        case .legs: return "Legs"
        case .abs: return "Abs"
        case .cardio: return "Cardio"
        }
    }

    /// Weekly working-set target used by the muscle-balance chart.
    var weeklySetTarget: Double {
        switch self {
        case .abs: return 6
        case .cardio: return 3
        default: return 10
        }
    }
}

struct FitExercise: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var muscle: FitMuscle
    var kind: FitExerciseKind
    var isCustom: Bool = false

    var symbol: String {
        switch kind {
        case .weight: return "dumbbell.fill"
        case .time: return "timer"
        case .cardio: return "flame.fill"
        }
    }

    /// Column labels for the set rows (first = load / distance column, second = reps / time column).
    func columnLabels(useKilograms: Bool) -> (String, String) {
        let unit = useKilograms ? "kg" : "lb"
        switch kind {
        case .weight: return (unit, "reps")
        case .time: return ("+\(unit)", "sec")
        case .cardio: return ("km", "min")
        }
    }
}

struct FitTemplateItem: Codable, Hashable, Identifiable {
    var id = UUID()
    var exerciseID: String
    var sets: Int
    var reps: Int
}

struct FitTemplate: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var muscles: [FitMuscle]
    var items: [FitTemplateItem]
    var isBuiltin: Bool = false

    var setCount: Int { items.reduce(0) { $0 + $1.sets } }
    /// Rough session length: ~2.6 min per working set including rest.
    var estimatedMinutes: Int { max(10, Int((Double(setCount) * 2.6).rounded())) }
    var muscleText: String { muscles.map(\.label).joined(separator: " · ") }
}

struct FitSet: Codable, Hashable, Identifiable {
    var id = UUID()
    var weight: Double
    var reps: Int
    var done: Bool = false
}

struct FitSessionExercise: Codable, Hashable, Identifiable {
    var id = UUID()
    var exerciseID: String
    var sets: [FitSet]
}

struct FitSession: Codable, Hashable, Identifiable {
    var id = UUID()
    var templateID: String?
    var name: String
    var start: Date
    var end: Date?
    var exercises: [FitSessionExercise]

    var duration: TimeInterval { max(0, (end ?? Date()).timeIntervalSince(start)) }
    var setCount: Int { exercises.reduce(0) { $0 + $1.sets.count } }
    var doneSetCount: Int { exercises.reduce(0) { $0 + $1.sets.filter(\.done).count } }
}

// MARK: - Food

enum FitMeal: String, Codable, CaseIterable, Identifiable {
    case breakfast, lunch, dinner, snacks

    var id: String { rawValue }

    var label: String {
        switch self {
        case .breakfast: return "Breakfast"
        case .lunch: return "Lunch"
        case .dinner: return "Dinner"
        case .snacks: return "Snacks"
        }
    }

    var symbol: String {
        switch self {
        case .breakfast: return "sunrise.fill"
        case .lunch: return "sun.max.fill"
        case .dinner: return "moon.stars.fill"
        case .snacks: return "carrot.fill"
        }
    }
}

/// Nutrition for one serving.
struct FitFood: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var serving: String
    var kcal: Double
    var protein: Double
    var carbs: Double
    var fat: Double
    var isCustom: Bool = false
}

struct FitFoodEntry: Codable, Identifiable, Hashable {
    var id = UUID()
    /// Local calendar day, `yyyy-MM-dd`.
    var day: String
    var meal: FitMeal
    var foodID: String?
    var name: String
    var serving: String
    var servings: Double
    /// Per-serving values, snapshotted so later edits to a custom food don't rewrite history.
    var kcal: Double
    var protein: Double
    var carbs: Double
    var fat: Double
    var loggedAt = Date()

    var totalKcal: Double { kcal * servings }
    var totalProtein: Double { protein * servings }
    var totalCarbs: Double { carbs * servings }
    var totalFat: Double { fat * servings }
}

struct FitMacroTotals: Equatable {
    var kcal: Double = 0
    var protein: Double = 0
    var carbs: Double = 0
    var fat: Double = 0

    static func sum(_ entries: [FitFoodEntry]) -> FitMacroTotals {
        entries.reduce(into: FitMacroTotals()) { t, e in
            t.kcal += e.totalKcal
            t.protein += e.totalProtein
            t.carbs += e.totalCarbs
            t.fat += e.totalFat
        }
    }
}

struct FitNutritionGoals: Codable, Hashable {
    var kcal: Int = 2200
    var protein: Int = 150
    var carbs: Int = 230
    var fat: Int = 70
}

struct FitSettings: Codable, Hashable {
    var useKilograms: Bool = true
    var restSeconds: Int = 90
    var weeklyGoal: Int = 4
}

/// The whole Fit document. Decoding tolerates missing keys so older files keep loading.
struct FitData: Codable {
    var settings = FitSettings()
    var customExercises: [FitExercise] = []
    var templates: [FitTemplate] = []
    /// Template id (or "rest") per weekday, Monday first.
    var plan: [String] = FitCatalog.splits[0].days
    /// Newest first.
    var sessions: [FitSession] = []
    var active: FitSession?
    var customFoods: [FitFood] = []
    var foodLog: [FitFoodEntry] = []
    var goals = FitNutritionGoals()

    enum CodingKeys: String, CodingKey {
        case settings, customExercises, templates, plan, sessions, active, customFoods, foodLog, goals
    }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let base = FitData()
        settings = try c.decodeIfPresent(FitSettings.self, forKey: .settings) ?? base.settings
        customExercises = try c.decodeIfPresent([FitExercise].self, forKey: .customExercises) ?? []
        templates = try c.decodeIfPresent([FitTemplate].self, forKey: .templates) ?? []
        let decodedPlan = try c.decodeIfPresent([String].self, forKey: .plan) ?? base.plan
        plan = decodedPlan.count == 7 ? decodedPlan : base.plan
        sessions = try c.decodeIfPresent([FitSession].self, forKey: .sessions) ?? []
        active = try c.decodeIfPresent(FitSession.self, forKey: .active)
        customFoods = try c.decodeIfPresent([FitFood].self, forKey: .customFoods) ?? []
        foodLog = try c.decodeIfPresent([FitFoodEntry].self, forKey: .foodLog) ?? []
        goals = try c.decodeIfPresent(FitNutritionGoals.self, forKey: .goals) ?? base.goals
    }
}
#endif
