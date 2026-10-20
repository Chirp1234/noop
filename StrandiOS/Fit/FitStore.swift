#if os(iOS)
import Foundation
import Combine
import os

struct FitBest: Hashable {
    var weight: Double
    var reps: Int
    var date: Date
}

struct FitRecord: Hashable, Identifiable {
    var id: String { exerciseID }
    var exerciseID: String
    var name: String
    var weight: Double
    var reps: Int
}

struct FitFinishSummary: Hashable {
    var session: FitSession
    var volume: Double
    var records: [FitRecord]
}

/// Owns the Fit document: loads it from Application Support, writes every change back atomically,
/// and answers the derived questions the screens ask (streaks, volume, personal bests, food totals).
/// Used from the main thread only (SwiftUI views and their actions).
final class FitStore: ObservableObject {
    static let shared = FitStore()

    @Published private(set) var data: FitData
    /// Drives the live-workout full-screen cover. Not persisted.
    @Published var isSessionPresented = false
    @Published private(set) var lastSaveFailed = false

    private let fileURL: URL
    private static let log = Logger(subsystem: "com.noop.fit", category: "store")

    init(fileURL: URL? = nil) {
        let url = fileURL ?? FitStore.defaultURL()
        self.fileURL = url
        self.data = FitStore.load(from: url)
    }

    // MARK: Persistence

    static func defaultURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("Fit", isDirectory: true).appendingPathComponent("fit.json")
    }

    private static func load(from url: URL) -> FitData {
        guard let raw = try? Data(contentsOf: url) else { return FitData() }
        do {
            return try JSONDecoder().decode(FitData.self, from: raw)
        } catch {
            // Keep the unreadable file next to the fresh one rather than overwriting it on next save.
            let stamp = Int(Date().timeIntervalSince1970)
            let copy = url.deletingLastPathComponent().appendingPathComponent("fit-unreadable-\(stamp).json")
            try? FileManager.default.copyItem(at: url, to: copy)
            log.error("Fit data unreadable, started fresh: \(error.localizedDescription, privacy: .public)")
            return FitData()
        }
    }

    /// Applies a change to a copy of the document, publishes it, and saves.
    func update(_ change: (inout FitData) -> Void) {
        var copy = data
        change(&copy)
        data = copy
        save()
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            let raw = try JSONEncoder().encode(data)
            try raw.write(to: fileURL, options: .atomic)
            if lastSaveFailed { lastSaveFailed = false }
        } catch {
            FitStore.log.error("Fit save failed: \(error.localizedDescription, privacy: .public)")
            lastSaveFailed = true
        }
    }

    /// Writes a dated copy of the document to the temporary directory for sharing.
    func exportBackup() throws -> URL {
        let name = "NOOP-Fit-\(FitStore.dayKey(Date())).json"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(data).write(to: url, options: .atomic)
        return url
    }

    func importBackup(from url: URL) throws {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        var decoded = try JSONDecoder().decode(FitData.self, from: Data(contentsOf: url))
        decoded.settings.restSeconds = min(600, max(15, decoded.settings.restSeconds))
        decoded.settings.weeklyGoal = min(7, max(1, decoded.settings.weeklyGoal))
        let restored = decoded
        update { $0 = restored }
    }

    func eraseAll() {
        update { $0 = FitData() }
    }

    // MARK: Lookups

    var allExercises: [FitExercise] { FitCatalog.exercises + data.customExercises }

    func exercise(_ id: String) -> FitExercise {
        allExercises.first { $0.id == id }
            ?? FitExercise(id: id, name: "Unknown exercise", muscle: .abs, kind: .weight)
    }

    var allTemplates: [FitTemplate] { data.templates + FitCatalog.templates }

    func template(_ id: String) -> FitTemplate? {
        allTemplates.first { $0.id == id }
    }

    var weightUnit: String { data.settings.useKilograms ? "kg" : "lb" }

    /// Sets from the most recent session that included this exercise.
    func lastSets(for exerciseID: String) -> [FitSet]? {
        for session in data.sessions {
            if let hit = session.exercises.first(where: { $0.exerciseID == exerciseID && !$0.sets.isEmpty }) {
                return hit.sets
            }
        }
        return nil
    }

    func setText(_ set: FitSet, kind: FitExerciseKind) -> String {
        let w = FitFormat.number(set.weight)
        switch kind {
        case .weight: return set.weight > 0 ? "\(w) \(weightUnit) × \(set.reps)" : "\(set.reps) reps"
        case .time: return set.weight > 0 ? "\(set.reps)s +\(w) \(weightUnit)" : "\(set.reps)s"
        case .cardio: return set.weight > 0 ? "\(w) km · \(set.reps) min" : "\(set.reps) min"
        }
    }

    // MARK: Templates & plan

    func saveTemplate(_ template: FitTemplate) {
        update { d in
            if let i = d.templates.firstIndex(where: { $0.id == template.id }) {
                d.templates[i] = template
            } else {
                d.templates.insert(template, at: 0)
            }
        }
    }

    func deleteTemplate(_ id: String) {
        update { d in
            d.templates.removeAll { $0.id == id }
            d.plan = d.plan.map { $0 == id ? FitCatalog.restID : $0 }
        }
    }

    func addCustomExercise(name: String, muscle: FitMuscle, kind: FitExerciseKind) -> FitExercise {
        let exercise = FitExercise(id: "cx-\(UUID().uuidString.prefix(8))", name: name,
                                   muscle: muscle, kind: kind, isCustom: true)
        update { $0.customExercises.append(exercise) }
        return exercise
    }

    func templateForToday(_ now: Date = Date()) -> FitTemplate? {
        let id = data.plan[FitStore.weekdayIndex(now)]
        return id == FitCatalog.restID ? nil : template(id)
    }

    /// The focus workout whose muscles have gone longest without training (never-trained wins).
    func suggestedTemplate(excluding excluded: String?) -> (template: FitTemplate, daysSince: Int?)? {
        var best: (FitTemplate, Int?)?
        for id in FitCatalog.focusTemplateIDs where id != excluded {
            guard let t = template(id) else { continue }
            let gap = daysSince(trained: t.muscles)
            guard let current = best else { best = (t, gap); continue }
            let currentGap = current.1 ?? Int.max
            if (gap ?? Int.max) > currentGap { best = (t, gap) }
        }
        return best.map { (template: $0.0, daysSince: $0.1) }
    }

    // MARK: Live workout

    func makeSessionExercise(_ exerciseID: String, sets: Int, reps: Int?) -> FitSessionExercise {
        let last = lastSets(for: exerciseID) ?? []
        let rows = (0..<max(1, sets)).map { i -> FitSet in
            let previous = i < last.count ? last[i] : last.last
            return FitSet(weight: previous?.weight ?? 0, reps: reps ?? previous?.reps ?? 10)
        }
        return FitSessionExercise(exerciseID: exerciseID, sets: rows)
    }

    func startWorkout(_ template: FitTemplate) {
        let exercises = template.items.map { makeSessionExercise($0.exerciseID, sets: $0.sets, reps: $0.reps) }
        let session = FitSession(templateID: template.id, name: template.name, start: Date(),
                                 end: nil, exercises: exercises)
        update { $0.active = session }
        isSessionPresented = true
    }

    func startEmptyWorkout() {
        let session = FitSession(templateID: nil, name: "Workout", start: Date(), end: nil, exercises: [])
        update { $0.active = session }
        isSessionPresented = true
    }

    func editActive(_ change: (inout FitSession) -> Void) {
        guard data.active != nil else { return }
        update { d in
            guard var active = d.active else { return }
            change(&active)
            d.active = active
        }
    }

    private func isValid(_ a: FitSession, _ e: Int, _ s: Int) -> Bool {
        a.exercises.indices.contains(e) && a.exercises[e].sets.indices.contains(s)
    }

    /// Returns true when the set is now marked done.
    @discardableResult
    func toggleSet(exercise e: Int, set s: Int) -> Bool {
        var nowDone = false
        editActive { a in
            guard isValid(a, e, s) else { return }
            a.exercises[e].sets[s].done.toggle()
            nowDone = a.exercises[e].sets[s].done
        }
        return nowDone
    }

    /// Sets a value and carries it down to later, untouched sets so a weight is typed once.
    func setWeight(_ value: Double, exercise e: Int, set s: Int) {
        editActive { a in
            guard isValid(a, e, s) else { return }
            let old = a.exercises[e].sets[s].weight
            a.exercises[e].sets[s].weight = max(0, value)
            for i in a.exercises[e].sets.indices where i > s {
                let row = a.exercises[e].sets[i]
                if !row.done && (row.weight == old || row.weight == 0) {
                    a.exercises[e].sets[i].weight = max(0, value)
                }
            }
        }
    }

    func setReps(_ value: Int, exercise e: Int, set s: Int) {
        editActive { a in
            guard isValid(a, e, s) else { return }
            let old = a.exercises[e].sets[s].reps
            a.exercises[e].sets[s].reps = max(0, value)
            for i in a.exercises[e].sets.indices where i > s {
                let row = a.exercises[e].sets[i]
                if !row.done && row.reps == old { a.exercises[e].sets[i].reps = max(0, value) }
            }
        }
    }

    func addSet(exercise e: Int) {
        editActive { a in
            guard a.exercises.indices.contains(e) else { return }
            let last = a.exercises[e].sets.last
            a.exercises[e].sets.append(FitSet(weight: last?.weight ?? 0, reps: last?.reps ?? 10))
        }
    }

    func removeLastSet(exercise e: Int) {
        editActive { a in
            guard a.exercises.indices.contains(e), a.exercises[e].sets.count > 1 else { return }
            a.exercises[e].sets.removeLast()
        }
    }

    func addExerciseToActive(_ exerciseID: String) {
        let p = FitCatalog.defaultPrescription(for: exercise(exerciseID).kind)
        let row = makeSessionExercise(exerciseID, sets: p.sets, reps: nil)
        editActive { $0.exercises.append(row) }
    }

    func moveActiveExercise(from e: Int, by offset: Int) {
        editActive { a in
            let target = e + offset
            guard a.exercises.indices.contains(e), a.exercises.indices.contains(target) else { return }
            a.exercises.swapAt(e, target)
        }
    }

    func removeActiveExercise(_ e: Int) {
        editActive { a in
            guard a.exercises.indices.contains(e) else { return }
            a.exercises.remove(at: e)
        }
    }

    /// Saves the ticked sets as a finished session. Returns nil when nothing was ticked.
    func finishWorkout() -> FitFinishSummary? {
        guard var active = data.active else { return nil }
        let kept = active.exercises.compactMap { e -> FitSessionExercise? in
            let done = e.sets.filter(\.done)
            return done.isEmpty ? nil : FitSessionExercise(id: e.id, exerciseID: e.exerciseID, sets: done)
        }
        guard !kept.isEmpty else { return nil }
        let before = personalBests(in: data.sessions)
        active.exercises = kept
        active.end = Date()
        let finished = active
        update { d in
            d.sessions.insert(finished, at: 0)
            d.active = nil
        }
        var records: [FitRecord] = []
        for (id, best) in personalBests(in: [finished]) {
            guard let previous = before[id], best.weight > previous.weight else { continue }
            records.append(FitRecord(exerciseID: id, name: exercise(id).name, weight: best.weight, reps: best.reps))
        }
        return FitFinishSummary(session: finished, volume: volume(of: finished),
                                records: records.sorted { $0.name < $1.name })
    }

    func discardWorkout() {
        update { $0.active = nil }
        isSessionPresented = false
    }

    func deleteSession(_ id: UUID) {
        update { $0.sessions.removeAll { $0.id == id } }
    }

    // MARK: Training stats

    static var calendar: Calendar {
        var cal = Calendar.current
        cal.firstWeekday = 2 // Monday
        return cal
    }

    static func startOfWeek(_ date: Date = Date()) -> Date {
        let cal = calendar
        return cal.dateInterval(of: .weekOfYear, for: date)?.start ?? cal.startOfDay(for: date)
    }

    /// 0 = Monday … 6 = Sunday.
    static func weekdayIndex(_ date: Date) -> Int {
        (calendar.component(.weekday, from: date) + 5) % 7
    }

    static func addDays(_ n: Int, to date: Date) -> Date {
        calendar.date(byAdding: .day, value: n, to: date) ?? date.addingTimeInterval(Double(n) * 86_400)
    }

    func sessions(since date: Date) -> [FitSession] {
        data.sessions.filter { $0.start >= date }
    }

    func sessionCount(inWeekStarting week: Date) -> Int {
        let end = FitStore.addDays(7, to: week)
        return data.sessions.filter { $0.start >= week && $0.start < end }.count
    }

    /// Consecutive weeks (ending this week, or last week if this one isn't done yet) meeting the goal.
    func weekStreak(now: Date = Date()) -> Int {
        let goal = data.settings.weeklyGoal
        var week = FitStore.startOfWeek(now)
        if sessionCount(inWeekStarting: week) < goal { week = FitStore.addDays(-7, to: week) }
        var streak = 0
        while streak < 520 && sessionCount(inWeekStarting: week) >= goal {
            streak += 1
            week = FitStore.addDays(-7, to: week)
        }
        return streak
    }

    var trainedDays: Set<Date> {
        let cal = FitStore.calendar
        return Set(data.sessions.map { cal.startOfDay(for: $0.start) })
    }

    func muscleSets(lastDays days: Int, now: Date = Date()) -> [FitMuscle: Int] {
        let since = FitStore.addDays(-(days - 1), to: FitStore.calendar.startOfDay(for: now))
        var out: [FitMuscle: Int] = [:]
        for session in sessions(since: since) {
            for e in session.exercises {
                out[exercise(e.exerciseID).muscle, default: 0] += e.sets.count
            }
        }
        return out
    }

    /// Whole days since any of these muscles were trained; nil if never.
    func daysSince(trained muscles: [FitMuscle], now: Date = Date()) -> Int? {
        let hit = data.sessions.first { s in
            s.exercises.contains { muscles.contains(exercise($0.exerciseID).muscle) }
        }
        guard let hit else { return nil }
        let cal = FitStore.calendar
        return cal.dateComponents([.day], from: cal.startOfDay(for: hit.start), to: cal.startOfDay(for: now)).day
    }

    /// Total load moved (weight × reps) across weighted exercises.
    func volume(of session: FitSession) -> Double {
        session.exercises.reduce(0) { sum, e in
            guard exercise(e.exerciseID).kind == .weight else { return sum }
            return sum + e.sets.reduce(0) { $0 + $1.weight * Double($1.reps) }
        }
    }

    /// Heaviest set per weighted exercise.
    func personalBests(in sessions: [FitSession]) -> [String: FitBest] {
        var best: [String: FitBest] = [:]
        for s in sessions {
            for e in s.exercises where exercise(e.exerciseID).kind == .weight {
                for set in e.sets where set.weight > 0 {
                    if let current = best[e.exerciseID],
                       current.weight > set.weight || (current.weight == set.weight && current.reps >= set.reps) {
                        continue
                    }
                    best[e.exerciseID] = FitBest(weight: set.weight, reps: set.reps, date: s.start)
                }
            }
        }
        return best
    }

    // MARK: Food

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func dayKey(_ date: Date) -> String { dayFormatter.string(from: date) }

    var allFoods: [FitFood] { data.customFoods + FitFoodCatalog.foods }

    func entries(on day: Date) -> [FitFoodEntry] {
        let key = FitStore.dayKey(day)
        return data.foodLog.filter { $0.day == key }.sorted { $0.loggedAt < $1.loggedAt }
    }

    func totals(on day: Date) -> FitMacroTotals {
        FitMacroTotals.sum(entries(on: day))
    }

    func logFood(_ food: FitFood, servings: Double, meal: FitMeal, day: Date) {
        let entry = FitFoodEntry(day: FitStore.dayKey(day), meal: meal, foodID: food.id, name: food.name,
                                 serving: food.serving, servings: servings, kcal: food.kcal,
                                 protein: food.protein, carbs: food.carbs, fat: food.fat)
        update { $0.foodLog.append(entry) }
    }

    func updateEntry(_ id: UUID, servings: Double, meal: FitMeal) {
        update { d in
            guard let i = d.foodLog.firstIndex(where: { $0.id == id }) else { return }
            d.foodLog[i].servings = servings
            d.foodLog[i].meal = meal
        }
    }

    func deleteEntry(_ id: UUID) {
        update { $0.foodLog.removeAll { $0.id == id } }
    }

    func saveCustomFood(_ food: FitFood) {
        update { d in
            if let i = d.customFoods.firstIndex(where: { $0.id == food.id }) {
                d.customFoods[i] = food
            } else {
                d.customFoods.insert(food, at: 0)
            }
        }
    }

    func deleteCustomFood(_ id: String) {
        update { $0.customFoods.removeAll { $0.id == id } }
    }

    /// Distinct foods from the log, most recently eaten first.
    func recentFoods(limit: Int = 20) -> [FitFood] {
        var seen = Set<String>()
        var out: [FitFood] = []
        for e in data.foodLog.sorted(by: { $0.loggedAt > $1.loggedAt }) {
            let key = e.foodID ?? "quick:\(e.name.lowercased()):\(FitFormat.whole(e.kcal))"
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            out.append(FitFood(id: key, name: e.name, serving: e.serving, kcal: e.kcal,
                               protein: e.protein, carbs: e.carbs, fat: e.fat))
            if out.count >= limit { break }
        }
        return out
    }
}

enum FitFormat {
    /// "60", "62.5", "0.25" — no trailing zeros.
    /// Values beyond this are typos, and converting them to Int would trap.
    private static let sane = 1e12

    static func number(_ value: Double) -> String {
        guard value.isFinite, abs(value) < sane else { return "—" }
        if value == value.rounded() { return String(Int(value)) }
        return value.formatted(.number.precision(.fractionLength(0...2)))
    }

    static func whole(_ value: Double) -> String {
        guard value.isFinite, abs(value) < sane else { return "—" }
        return Int(value.rounded()).formatted()
    }

    static func clock(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval))
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    static func minutes(_ interval: TimeInterval) -> String {
        let m = Int((interval / 60).rounded())
        return m >= 60 ? "\(m / 60)h \(m % 60)m" : "\(m)m"
    }
}
#endif
