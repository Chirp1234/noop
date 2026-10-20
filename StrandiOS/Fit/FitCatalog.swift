#if os(iOS)
import Foundation

/// Built-in content for the Fit tab: exercise library, ready-made day options, weekly splits.
enum FitCatalog {
    struct Split: Identifiable, Hashable {
        let id: String
        let name: String
        /// Template id or "rest" per weekday, Monday first.
        let days: [String]
    }

    static let restID = "rest"
    static let weekdays = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
    static let weekdaysLong = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]

    /// Single-focus options the "suggested" pick chooses between.
    static let focusTemplateIDs = ["chest", "back", "shoulders", "arms", "legs", "abs"]

    private static func ex(_ id: String, _ name: String, _ muscle: FitMuscle,
                           _ kind: FitExerciseKind = .weight) -> FitExercise {
        FitExercise(id: id, name: name, muscle: muscle, kind: kind)
    }

    static let exercises: [FitExercise] = [
        // Chest
        ex("bench-press", "Barbell bench press", .chest),
        ex("incline-bench", "Incline bench press", .chest),
        ex("incline-db-press", "Incline dumbbell press", .chest),
        ex("db-bench", "Dumbbell bench press", .chest),
        ex("chest-fly", "Cable fly", .chest),
        ex("pec-deck", "Pec deck", .chest),
        ex("dips-chest", "Chest dips", .chest),
        ex("push-up", "Push-up", .chest),
        // Back
        ex("deadlift", "Deadlift", .back),
        ex("pull-up", "Pull-up", .back),
        ex("chin-up", "Chin-up", .back),
        ex("lat-pulldown", "Lat pulldown", .back),
        ex("barbell-row", "Barbell row", .back),
        ex("db-row", "One-arm dumbbell row", .back),
        ex("seated-row", "Seated cable row", .back),
        ex("t-bar-row", "T-bar row", .back),
        ex("straight-arm-pulldown", "Straight-arm pulldown", .back),
        // Shoulders
        ex("ohp", "Overhead press", .shoulders),
        ex("db-shoulder-press", "Dumbbell shoulder press", .shoulders),
        ex("arnold-press", "Arnold press", .shoulders),
        ex("lateral-raise", "Lateral raise", .shoulders),
        ex("rear-delt-fly", "Rear delt fly", .shoulders),
        ex("front-raise", "Front raise", .shoulders),
        ex("face-pull", "Face pull", .shoulders),
        ex("upright-row", "Upright row", .shoulders),
        // Biceps
        ex("barbell-curl", "Barbell curl", .biceps),
        ex("db-curl", "Dumbbell curl", .biceps),
        ex("hammer-curl", "Hammer curl", .biceps),
        ex("preacher-curl", "Preacher curl", .biceps),
        ex("incline-curl", "Incline dumbbell curl", .biceps),
        ex("cable-curl", "Cable curl", .biceps),
        ex("concentration-curl", "Concentration curl", .biceps),
        // Triceps
        ex("tricep-pushdown", "Tricep pushdown", .triceps),
        ex("skull-crusher", "Skull crusher", .triceps),
        ex("overhead-ext", "Overhead tricep extension", .triceps),
        ex("close-grip-bench", "Close-grip bench press", .triceps),
        ex("dips", "Tricep dips", .triceps),
        ex("kickback", "Tricep kickback", .triceps),
        // Legs
        ex("squat", "Back squat", .legs),
        ex("front-squat", "Front squat", .legs),
        ex("goblet-squat", "Goblet squat", .legs),
        ex("leg-press", "Leg press", .legs),
        ex("rdl", "Romanian deadlift", .legs),
        ex("lunge", "Walking lunge", .legs),
        ex("bulgarian-split", "Bulgarian split squat", .legs),
        ex("leg-ext", "Leg extension", .legs),
        ex("leg-curl", "Leg curl", .legs),
        ex("hip-thrust", "Hip thrust", .legs),
        ex("calf-raise", "Standing calf raise", .legs),
        // Abs
        ex("crunch", "Crunch", .abs),
        ex("hanging-leg-raise", "Hanging leg raise", .abs),
        ex("cable-crunch", "Cable crunch", .abs),
        ex("russian-twist", "Russian twist", .abs),
        ex("ab-wheel", "Ab wheel rollout", .abs),
        ex("bicycle-crunch", "Bicycle crunch", .abs),
        ex("dead-bug", "Dead bug", .abs),
        ex("plank", "Plank", .abs, .time),
        ex("side-plank", "Side plank", .abs, .time),
        // Cardio
        ex("run", "Run", .cardio, .cardio),
        ex("bike", "Bike", .cardio, .cardio),
        ex("rower", "Rower", .cardio, .cardio),
        ex("stairmaster", "Stair climber", .cardio, .cardio),
        ex("jump-rope", "Jump rope", .cardio, .time),
    ]

    private static func tpl(_ id: String, _ name: String, _ muscles: [FitMuscle],
                            _ items: [(String, Int, Int)]) -> FitTemplate {
        FitTemplate(id: id, name: name, muscles: muscles,
                    items: items.map { FitTemplateItem(exerciseID: $0.0, sets: $0.1, reps: $0.2) },
                    isBuiltin: true)
    }

    static let templates: [FitTemplate] = [
        tpl("push", "Push", [.chest, .shoulders, .triceps], [
            ("bench-press", 4, 8), ("ohp", 3, 8), ("incline-db-press", 3, 10),
            ("lateral-raise", 3, 15), ("tricep-pushdown", 3, 12), ("overhead-ext", 3, 12),
        ]),
        tpl("pull", "Pull", [.back, .biceps], [
            ("deadlift", 3, 5), ("pull-up", 3, 8), ("barbell-row", 3, 8),
            ("face-pull", 3, 15), ("barbell-curl", 3, 10), ("hammer-curl", 3, 12),
        ]),
        tpl("legs", "Legs", [.legs], [
            ("squat", 4, 6), ("rdl", 3, 8), ("leg-press", 3, 12),
            ("leg-curl", 3, 12), ("calf-raise", 4, 15),
        ]),
        tpl("upper", "Upper body", [.chest, .back, .shoulders, .biceps, .triceps], [
            ("bench-press", 4, 6), ("barbell-row", 4, 8), ("ohp", 3, 8),
            ("lat-pulldown", 3, 10), ("db-curl", 2, 12), ("tricep-pushdown", 2, 12),
        ]),
        tpl("lower", "Lower body", [.legs, .abs], [
            ("squat", 4, 6), ("rdl", 3, 8), ("bulgarian-split", 3, 10),
            ("leg-ext", 3, 12), ("calf-raise", 3, 15), ("hanging-leg-raise", 3, 12),
        ]),
        tpl("chest", "Chest", [.chest], [
            ("bench-press", 4, 8), ("incline-db-press", 3, 10), ("chest-fly", 3, 12),
            ("dips-chest", 3, 10), ("push-up", 2, 15),
        ]),
        tpl("back", "Back", [.back], [
            ("pull-up", 4, 8), ("barbell-row", 4, 8), ("lat-pulldown", 3, 10),
            ("seated-row", 3, 12), ("straight-arm-pulldown", 3, 12),
        ]),
        tpl("shoulders", "Shoulders", [.shoulders], [
            ("ohp", 4, 8), ("arnold-press", 3, 10), ("lateral-raise", 4, 15),
            ("rear-delt-fly", 3, 15), ("face-pull", 3, 15),
        ]),
        tpl("arms", "Arms", [.biceps, .triceps], [
            ("barbell-curl", 3, 10), ("close-grip-bench", 3, 8), ("hammer-curl", 3, 12),
            ("skull-crusher", 3, 10), ("preacher-curl", 3, 12), ("tricep-pushdown", 3, 12),
        ]),
        tpl("biceps", "Biceps", [.biceps], [
            ("barbell-curl", 4, 10), ("incline-curl", 3, 12), ("hammer-curl", 3, 12),
            ("preacher-curl", 3, 12), ("cable-curl", 2, 15),
        ]),
        tpl("triceps", "Triceps", [.triceps], [
            ("close-grip-bench", 4, 8), ("skull-crusher", 3, 10), ("tricep-pushdown", 3, 12),
            ("overhead-ext", 3, 12), ("kickback", 2, 15),
        ]),
        tpl("abs", "Abs", [.abs], [
            ("hanging-leg-raise", 3, 12), ("cable-crunch", 3, 15), ("plank", 3, 60),
            ("russian-twist", 3, 20), ("ab-wheel", 3, 10),
        ]),
        tpl("full", "Full body", [.legs, .chest, .back, .shoulders, .abs], [
            ("squat", 3, 8), ("bench-press", 3, 8), ("barbell-row", 3, 8),
            ("ohp", 3, 10), ("rdl", 3, 10), ("plank", 3, 45),
        ]),
        tpl("cardio", "Cardio", [.cardio], [
            ("run", 1, 25), ("jump-rope", 3, 60),
        ]),
    ]

    static let splits: [Split] = [
        Split(id: "ppl", name: "Push / Pull / Legs", days: ["push", "pull", "legs", "rest", "push", "pull", "legs"]),
        Split(id: "ul", name: "Upper / Lower", days: ["upper", "lower", "rest", "upper", "lower", "abs", "rest"]),
        Split(id: "bro", name: "Bro split", days: ["chest", "back", "shoulders", "arms", "legs", "abs", "rest"]),
        Split(id: "full", name: "Full body 3×", days: ["full", "rest", "full", "rest", "full", "cardio", "rest"]),
    ]

    /// Sensible starting sets/reps when an exercise is added by hand.
    static func defaultPrescription(for kind: FitExerciseKind) -> (sets: Int, reps: Int) {
        switch kind {
        case .weight: return (3, 10)
        case .time: return (3, 45)
        case .cardio: return (1, 20)
        }
    }
}
#endif
