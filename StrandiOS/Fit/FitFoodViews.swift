#if os(iOS)
import SwiftUI
import StrandDesign

/// Food half of the Fit tab: calories left today, macros, meals, and the last 7 days.
struct FitFoodHome: View {
    @ObservedObject private var store = FitStore.shared
    @State private var day = FitStore.calendar.startOfDay(for: Date())
    @State private var addingTo: FitMeal?
    @State private var editing: FitFoodEntry?
    @State private var showGoals = false

    private var isToday: Bool { FitStore.calendar.isDateInToday(day) }

    var body: some View {
        let entries = store.entries(on: day)
        let totals = FitMacroTotals.sum(entries)
        VStack(alignment: .leading, spacing: 16) {
            dayBar
            caloriesCard(totals)
            ForEach(FitMeal.allCases) { meal in
                mealCard(meal, entries: entries.filter { $0.meal == meal })
            }
            weekCard
        }
        .sheet(item: $addingTo) { meal in FitFoodAddSheet(meal: meal, day: day) }
        .sheet(item: $editing) { FitFoodEntryEditor(entry: $0) }
        .sheet(isPresented: $showGoals) { FitGoalsSheet() }
    }

    // MARK: Sections

    private var dayBar: some View {
        HStack {
            Button { shiftDay(-1) } label: {
                Image(systemName: "chevron.left").frame(width: 44, height: 44)
            }
            .accessibilityLabel("Previous day")
            Spacer()
            VStack(spacing: 0) {
                Text(dayTitle).font(StrandFont.headline)
                if !isToday {
                    Button("Back to today") { day = FitStore.calendar.startOfDay(for: Date()) }
                        .font(StrandFont.caption)
                        .foregroundStyle(StrandPalette.accent)
                }
            }
            Spacer()
            Button { shiftDay(1) } label: {
                Image(systemName: "chevron.right").frame(width: 44, height: 44)
            }
            .disabled(isToday)
            .opacity(isToday ? StrandPalette.disabledOpacity : 1)
            .accessibilityLabel("Next day")
        }
        .font(StrandFont.headline)
        .foregroundStyle(StrandPalette.textPrimary)
        .buttonStyle(.plain)
    }

    private var dayTitle: String {
        let cal = FitStore.calendar
        if cal.isDateInToday(day) { return "Today" }
        if cal.isDateInYesterday(day) { return "Yesterday" }
        return day.formatted(.dateTime.weekday(.wide).day().month(.abbreviated))
    }

    private func caloriesCard(_ totals: FitMacroTotals) -> some View {
        let goals = store.data.goals
        let goal = Double(max(1, goals.kcal))
        let left = goal - totals.kcal
        let fraction = totals.kcal / goal
        let ringColor = fraction > 1.05 ? StrandPalette.statusWarning : StrandPalette.statusPositive
        return NoopCard {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    FitCardLabel(title: "Calories", symbol: "flame.fill")
                    Button { showGoals = true } label: {
                        Label("Goals", systemImage: "target")
                            .font(StrandFont.caption)
                            .foregroundStyle(StrandPalette.textSecondary)
                            .padding(.horizontal, 10).frame(height: 28)
                            .background(Capsule().fill(StrandPalette.surfaceInset))
                    }
                    .buttonStyle(.plain)
                }
                HStack(spacing: 20) {
                    ZStack {
                        Circle().stroke(StrandPalette.surfaceInset, lineWidth: 12)
                        Circle()
                            .trim(from: 0, to: CGFloat(min(1, fraction)))
                            .stroke(ringColor, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .animation(.easeOut(duration: 0.5), value: fraction)
                        VStack(spacing: 0) {
                            Text(FitFormat.whole(abs(left)))
                                .font(StrandFont.number(30, weight: .light))
                                .contentTransition(.numericText())
                            Text(left >= 0 ? "kcal left" : "kcal over")
                                .font(StrandFont.caption)
                                .foregroundStyle(left >= 0 ? StrandPalette.textTertiary : StrandPalette.statusWarning)
                        }
                    }
                    .frame(width: 128, height: 128)
                    VStack(alignment: .leading, spacing: 10) {
                        figure("Eaten", FitFormat.whole(totals.kcal), "kcal")
                        figure("Goal", FitFormat.whole(goal), "kcal")
                    }
                }
                macroBar("Protein", totals.protein, Double(goals.protein), StrandPalette.metricCyan)
                macroBar("Carbs", totals.carbs, Double(goals.carbs), StrandPalette.metricAmber)
                macroBar("Fat", totals.fat, Double(goals.fat), StrandPalette.metricRose)
            }
        }
    }

    private func figure(_ label: String, _ value: String, _ unit: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label).font(StrandFont.caption).foregroundStyle(StrandPalette.textTertiary)
            FitBigNumber(value: value, unit: unit, size: 26)
        }
    }

    private func macroBar(_ name: String, _ value: Double, _ goal: Double, _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(name).font(StrandFont.subhead).foregroundStyle(StrandPalette.textSecondary)
                Spacer()
                Text("\(FitFormat.whole(value)) / \(FitFormat.whole(goal)) g")
                    .font(StrandFont.captionNumber).foregroundStyle(StrandPalette.textSecondary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(StrandPalette.surfaceInset)
                    Capsule().fill(tint)
                        .frame(width: geo.size.width * CGFloat(min(1, goal > 0 ? value / goal : 0)))
                }
            }
            .frame(height: 8)
        }
    }

    private func mealCard(_ meal: FitMeal, entries: [FitFoodEntry]) -> some View {
        let kcal = entries.reduce(0) { $0 + $1.totalKcal }
        return NoopCard(padding: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 12) {
                    FitIconTile(symbol: meal.symbol, size: 36)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(meal.label).font(StrandFont.headline).foregroundStyle(StrandPalette.textPrimary)
                        Text(entries.isEmpty ? "Nothing logged" : "\(FitFormat.whole(kcal)) kcal")
                            .font(StrandFont.caption).foregroundStyle(StrandPalette.textTertiary)
                    }
                    Spacer()
                    Button { addingTo = meal } label: {
                        Image(systemName: "plus")
                            .font(StrandFont.headline)
                            .foregroundStyle(StrandPalette.surfaceRaised)
                            .frame(width: 36, height: 36)
                            .background(Circle().fill(StrandPalette.textPrimary))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Add to \(meal.label)")
                }
                ForEach(entries) { entry in
                    Divider().overlay(StrandPalette.hairline).padding(.leading, 48)
                    Button { editing = entry } label: { entryRow(entry) }
                        .buttonStyle(.plain)
                }
            }
        }
    }

    private func entryRow(_ e: FitFoodEntry) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(e.name).font(StrandFont.subhead).foregroundStyle(StrandPalette.textPrimary).lineLimit(1)
                Text("\(FitFormat.number(e.servings)) × \(e.serving) · P \(FitFormat.whole(e.totalProtein)) C \(FitFormat.whole(e.totalCarbs)) F \(FitFormat.whole(e.totalFat))")
                    .font(StrandFont.caption).foregroundStyle(StrandPalette.textTertiary).lineLimit(1)
            }
            Spacer(minLength: 0)
            Text(FitFormat.whole(e.totalKcal)).font(StrandFont.bodyNumber).foregroundStyle(StrandPalette.textPrimary)
        }
        .padding(.leading, 48)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }

    private var weekCard: some View {
        let goal = Double(max(1, store.data.goals.kcal))
        let days = (0..<7).map { FitStore.addDays($0 - 6, to: day) }
        let values = days.map { store.totals(on: $0).kcal }
        let logged = values.filter { $0 > 0 }
        let average = logged.isEmpty ? 0 : logged.reduce(0, +) / Double(logged.count)
        let scale = max(goal * 1.25, values.max() ?? 0)
        return NoopCard {
            VStack(alignment: .leading, spacing: 12) {
                FitCardLabel(title: "Last 7 days", symbol: "chart.bar.fill",
                             trailing: logged.isEmpty ? nil : "avg \(FitFormat.whole(average)) kcal")
                HStack(alignment: .bottom, spacing: 4) {
                    ForEach(Array(days.enumerated()), id: \.offset) { i, d in
                        let v = values[i]
                        FitColumn(fraction: v / scale,
                                  tint: v > goal * 1.05 ? StrandPalette.statusWarning : StrandPalette.statusPositive,
                                  valueText: v > 0 ? FitFormat.whole(v) : " ",
                                  label: FitCatalog.weekdays[FitStore.weekdayIndex(d)],
                                  height: 90,
                                  highlighted: i == 6)
                    }
                }
            }
        }
    }

    private func shiftDay(_ n: Int) {
        let next = FitStore.addDays(n, to: day)
        guard next <= FitStore.calendar.startOfDay(for: Date()) else { return }
        day = next
    }
}

// MARK: - Entry editor

struct FitFoodEntryEditor: View {
    let entry: FitFoodEntry
    @ObservedObject private var store = FitStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var servings: Double = 1
    @State private var meal: FitMeal = .breakfast

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(entry.name).font(StrandFont.headline)
                    Text("1 serving = \(entry.serving)").foregroundStyle(StrandPalette.textSecondary)
                }
                Section("Amount") {
                    FitServingsField(servings: $servings)
                    Picker("Meal", selection: $meal) {
                        ForEach(FitMeal.allCases) { Text($0.label).tag($0) }
                    }
                }
                Section("Nutrition") {
                    FitNutritionSummary(kcal: entry.kcal * servings, protein: entry.protein * servings,
                                        carbs: entry.carbs * servings, fat: entry.fat * servings)
                }
                Section {
                    Button("Delete entry", role: .destructive) {
                        store.deleteEntry(entry.id)
                        dismiss()
                    }
                }
            }
            .fitKeyboardDone()
            .navigationTitle("Edit entry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        store.updateEntry(entry.id, servings: servings, meal: meal)
                        dismiss()
                    }
                    .disabled(servings <= 0)
                }
            }
            .onAppear {
                servings = entry.servings
                meal = entry.meal
            }
        }
    }
}

// MARK: - Goals

struct FitGoalsSheet: View {
    @ObservedObject private var store = FitStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var goals = FitNutritionGoals()

    var body: some View {
        let macroKcal = goals.protein * 4 + goals.carbs * 4 + goals.fat * 9
        NavigationStack {
            Form {
                Section {
                    goalField("Calories", value: $goals.kcal, unit: "kcal")
                } footer: {
                    Text("A common starting point is bodyweight in lb × 14–16 to maintain; subtract 300–500 to lose fat.")
                }
                Section {
                    goalField("Protein", value: $goals.protein, unit: "g")
                    goalField("Carbs", value: $goals.carbs, unit: "g")
                    goalField("Fat", value: $goals.fat, unit: "g")
                } header: {
                    Text("Macros")
                } footer: {
                    Text("These macros add up to \(macroKcal) kcal.")
                }
            }
            .fitKeyboardDone()
            .navigationTitle("Daily goals")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let saved = goals
                        store.update { $0.goals = saved }
                        dismiss()
                    }
                    .disabled(goals.kcal <= 0)
                }
            }
            .onAppear { goals = store.data.goals }
        }
    }

    private func goalField(_ label: String, value: Binding<Int>, unit: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            TextField("0", value: value, format: .number)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 90)
            Text(unit).foregroundStyle(StrandPalette.textTertiary).frame(width: 36, alignment: .leading)
        }
    }
}

// MARK: - Shared food pieces

/// Servings stepper with a direct-entry field, in quarter-serving steps.
struct FitServingsField: View {
    @Binding var servings: Double

    var body: some View {
        HStack {
            Text("Servings")
            Spacer()
            TextField("1", value: $servings, format: .number)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 64)
            Stepper("Servings", value: $servings, in: 0.25...50, step: 0.25)
                .labelsHidden()
        }
    }
}

struct FitNutritionSummary: View {
    let kcal: Double
    let protein: Double
    let carbs: Double
    let fat: Double

    var body: some View {
        HStack {
            cell(FitFormat.whole(kcal), "kcal")
            cell(FitFormat.number((protein * 10).rounded() / 10), "protein")
            cell(FitFormat.number((carbs * 10).rounded() / 10), "carbs")
            cell(FitFormat.number((fat * 10).rounded() / 10), "fat")
        }
    }

    private func cell(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(StrandFont.number(18, weight: .medium))
            Text(label).font(StrandFont.caption).foregroundStyle(StrandPalette.textTertiary)
        }
        .frame(maxWidth: .infinity)
    }
}
#endif
