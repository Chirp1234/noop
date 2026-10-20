#if os(iOS)
import SwiftUI
import StrandDesign

/// Search the food list, recent foods and custom foods; log an amount to a meal. Stays open so
/// several foods can be added in one go.
struct FitFoodAddSheet: View {
    enum Source: String, CaseIterable, Hashable {
        case all, recent, mine
        var label: String {
            switch self {
            case .all: return "All foods"
            case .recent: return "Recent"
            case .mine: return "My foods"
            }
        }
    }

    let day: Date
    @State private var meal: FitMeal
    @ObservedObject private var store = FitStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var source: Source
    @State private var addedCount = 0

    init(meal: FitMeal, day: Date) {
        self.day = day
        _meal = State(initialValue: meal)
        _source = State(initialValue: FitStore.shared.data.foodLog.isEmpty ? .all : .recent)
    }

    private var results: [FitFood] {
        let pool: [FitFood]
        switch source {
        case .all: pool = store.allFoods
        case .recent: pool = store.recentFoods()
        case .mine: pool = store.data.customFoods
        }
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return pool }
        return pool.filter { $0.name.lowercased().contains(q) }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Meal", selection: $meal) {
                        ForEach(FitMeal.allCases) { Text($0.label).tag($0) }
                    }
                    Picker("Show", selection: $source) {
                        ForEach(Source.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
                Section {
                    NavigationLink {
                        FitQuickAddForm(meal: meal, day: day) { addedCount += 1 }
                    } label: {
                        Label("Quick add calories", systemImage: "bolt.fill")
                    }
                    NavigationLink {
                        FitCustomFoodForm(meal: meal, day: day) { addedCount += 1 }
                    } label: {
                        Label("Create a food", systemImage: "square.and.pencil")
                    }
                }
                Section {
                    if results.isEmpty {
                        Text(emptyText).foregroundStyle(StrandPalette.textTertiary)
                    }
                    ForEach(results) { food in
                        NavigationLink {
                            FitFoodAmountView(food: food, meal: meal, day: day) { addedCount += 1 }
                        } label: {
                            foodRow(food)
                        }
                        .swipeActions {
                            if food.isCustom {
                                Button(role: .destructive) { store.deleteCustomFood(food.id) } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
            }
            .searchable(text: $query, prompt: "Search foods")
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }

    private var title: String {
        addedCount == 0 ? "Add to \(meal.label)" : "\(addedCount) added"
    }

    private var emptyText: String {
        switch source {
        case .recent: return "Foods you log show up here."
        case .mine: return "Create a food to keep it here."
        case .all: return "No matches. Try Quick add or Create a food."
        }
    }

    private func foodRow(_ food: FitFood) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(food.name).foregroundStyle(StrandPalette.textPrimary)
                Text("\(food.serving) · P \(FitFormat.whole(food.protein)) C \(FitFormat.whole(food.carbs)) F \(FitFormat.whole(food.fat))")
                    .font(StrandFont.caption).foregroundStyle(StrandPalette.textTertiary)
            }
            Spacer()
            Text("\(FitFormat.whole(food.kcal))").font(StrandFont.bodyNumber)
            Text("kcal").font(StrandFont.caption).foregroundStyle(StrandPalette.textTertiary)
        }
    }
}

// MARK: - Amount

struct FitFoodAmountView: View {
    let food: FitFood
    let meal: FitMeal
    let day: Date
    let onAdded: () -> Void
    @ObservedObject private var store = FitStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var servings: Double = 1

    var body: some View {
        Form {
            Section {
                Text(food.name).font(StrandFont.headline)
                Text("1 serving = \(food.serving)").foregroundStyle(StrandPalette.textSecondary)
            }
            Section("Amount") {
                FitServingsField(servings: $servings)
                HStack(spacing: 8) {
                    ForEach([0.5, 1, 1.5, 2], id: \.self) { preset in
                        FitChip(title: "\(FitFormat.number(preset))×", selected: servings == preset) {
                            servings = preset
                        }
                    }
                }
            }
            Section("Nutrition") {
                FitNutritionSummary(kcal: food.kcal * servings, protein: food.protein * servings,
                                    carbs: food.carbs * servings, fat: food.fat * servings)
            }
            Section {
                Button {
                    store.logFood(food, servings: servings, meal: meal, day: day)
                    onAdded()
                    dismiss()
                } label: {
                    Text("Add to \(meal.label)").font(StrandFont.headline).frame(maxWidth: .infinity)
                }
                .disabled(servings <= 0)
            }
        }
        .fitKeyboardDone()
        .navigationTitle("Amount")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Quick add

struct FitQuickAddForm: View {
    let meal: FitMeal
    let day: Date
    let onAdded: () -> Void
    @ObservedObject private var store = FitStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var kcal: Double = 0
    @State private var protein: Double = 0
    @State private var carbs: Double = 0
    @State private var fat: Double = 0

    var body: some View {
        Form {
            Section {
                TextField("What was it? (optional)", text: $name)
                FitNumberRow(label: "Calories", unit: "kcal", value: $kcal)
            }
            Section("Macros (optional)") {
                FitNumberRow(label: "Protein", unit: "g", value: $protein)
                FitNumberRow(label: "Carbs", unit: "g", value: $carbs)
                FitNumberRow(label: "Fat", unit: "g", value: $fat)
            }
            Section {
                Button {
                    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                    let food = FitFood(id: "quick-\(UUID().uuidString.prefix(8))",
                                       name: trimmed.isEmpty ? "Quick add" : String(trimmed.prefix(48)),
                                       serving: "1 portion", kcal: kcal, protein: protein, carbs: carbs, fat: fat)
                    store.logFood(food, servings: 1, meal: meal, day: day)
                    onAdded()
                    dismiss()
                } label: {
                    Text("Add to \(meal.label)").font(StrandFont.headline).frame(maxWidth: .infinity)
                }
                .disabled(kcal <= 0)
            }
        }
        .fitKeyboardDone()
        .navigationTitle("Quick add")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Custom food

struct FitCustomFoodForm: View {
    let meal: FitMeal
    let day: Date
    let onAdded: () -> Void
    @ObservedObject private var store = FitStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var serving = "1 serving"
    @State private var kcal: Double = 0
    @State private var protein: Double = 0
    @State private var carbs: Double = 0
    @State private var fat: Double = 0
    @State private var logNow = true

    var body: some View {
        Form {
            Section("Food") {
                TextField("Name", text: $name)
                TextField("Serving, e.g. 1 bowl (250 g)", text: $serving)
            }
            Section("Per serving") {
                FitNumberRow(label: "Calories", unit: "kcal", value: $kcal)
                FitNumberRow(label: "Protein", unit: "g", value: $protein)
                FitNumberRow(label: "Carbs", unit: "g", value: $carbs)
                FitNumberRow(label: "Fat", unit: "g", value: $fat)
            }
            Section {
                Toggle("Also add 1 serving to \(meal.label)", isOn: $logNow)
                Button {
                    save()
                } label: {
                    Text("Save food").font(StrandFont.headline).frame(maxWidth: .infinity)
                }
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || kcal < 0)
            }
        }
        .fitKeyboardDone()
        .navigationTitle("Create a food")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func save() {
        let trimmedServing = serving.trimmingCharacters(in: .whitespacesAndNewlines)
        let food = FitFood(id: "cf-\(UUID().uuidString.prefix(8))",
                           name: String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(48)),
                           serving: trimmedServing.isEmpty ? "1 serving" : String(trimmedServing.prefix(40)),
                           kcal: max(0, kcal), protein: max(0, protein), carbs: max(0, carbs), fat: max(0, fat),
                           isCustom: true)
        store.saveCustomFood(food)
        if logNow {
            store.logFood(food, servings: 1, meal: meal, day: day)
            onAdded()
        }
        dismiss()
    }
}

struct FitNumberRow: View {
    let label: String
    let unit: String
    @Binding var value: Double

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            TextField("0", value: $value, format: .number)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 90)
            Text(unit).foregroundStyle(StrandPalette.textTertiary).frame(width: 36, alignment: .leading)
        }
    }
}
#endif
