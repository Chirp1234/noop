#if os(iOS)
import SwiftUI
import StrandDesign

// MARK: - Weekly plan

struct FitPlanView: View {
    @ObservedObject private var store = FitStore.shared

    var body: some View {
        let now = Date()
        let today = FitStore.weekdayIndex(now)
        let weekStart = FitStore.startOfWeek(now)
        let doneDays = Set(store.sessions(since: weekStart).map { FitStore.weekdayIndex($0.start) })
        let trainingDays = store.data.plan.filter { $0 != FitCatalog.restID }.count
        let currentSplit = FitCatalog.splits.first { $0.days == store.data.plan }?.id

        ScreenScaffold(title: "Weekly plan", subtitle: "\(trainingDays) training days each week") {
            NoopCard {
                VStack(alignment: .leading, spacing: 12) {
                    FitCardLabel(title: "Split", symbol: "square.stack.3d.up.fill",
                                 trailing: currentSplit == nil ? "Custom" : nil)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(FitCatalog.splits) { split in
                                FitChip(title: split.name, selected: split.id == currentSplit) {
                                    store.update { $0.plan = split.days }
                                }
                            }
                        }
                    }
                }
            }
            NoopCard(padding: 8) {
                VStack(spacing: 0) {
                    ForEach(0..<7, id: \.self) { i in
                        dayRow(i, isToday: i == today, done: doneDays.contains(i), weekStart: weekStart)
                        if i < 6 { Divider().overlay(StrandPalette.hairline).padding(.leading, 64) }
                    }
                }
            }
            NoopCard {
                Stepper(value: Binding(get: { store.data.settings.weeklyGoal },
                                       set: { v in store.update { $0.settings.weeklyGoal = v } }),
                        in: 1...7) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Weekly goal: \(store.data.settings.weeklyGoal)").font(StrandFont.headline)
                        Text("Workouts per week that count toward your streak")
                            .font(StrandFont.caption).foregroundStyle(StrandPalette.textTertiary)
                    }
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
    }

    private func dayRow(_ i: Int, isToday: Bool, done: Bool, weekStart: Date) -> some View {
        let id = store.data.plan[i]
        let t = id == FitCatalog.restID ? nil : store.template(id)
        let date = FitStore.calendar.component(.day, from: FitStore.addDays(i, to: weekStart))
        return Menu {
            Button { setDay(i, FitCatalog.restID) } label: { Label("Rest", systemImage: "moon.zzz") }
            ForEach(store.allTemplates) { option in
                Button { setDay(i, option.id) } label: {
                    if option.id == id { Label(option.name, systemImage: "checkmark") } else { Text(option.name) }
                }
            }
        } label: {
            HStack(spacing: 12) {
                VStack(spacing: 0) {
                    Text(FitCatalog.weekdays[i].uppercased()).font(StrandFont.overline)
                    Text("\(date)").font(StrandFont.headline)
                }
                .foregroundStyle(isToday ? StrandPalette.surfaceRaised : StrandPalette.textPrimary)
                .frame(width: 44, height: 48)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isToday ? StrandPalette.textPrimary : StrandPalette.surfaceInset))
                VStack(alignment: .leading, spacing: 2) {
                    Text(t?.name ?? "Rest").font(StrandFont.headline).foregroundStyle(StrandPalette.textPrimary)
                    Text(t?.muscleText ?? "Recovery day").font(StrandFont.caption)
                        .foregroundStyle(StrandPalette.textTertiary).lineLimit(1)
                }
                Spacer(minLength: 0)
                if done {
                    FitStatusDot(text: "Done", color: StrandPalette.statusPositive)
                } else if isToday {
                    FitStatusDot(text: "Today", color: StrandPalette.statusWarning)
                }
                Image(systemName: "chevron.up.chevron.down").font(StrandFont.caption)
                    .foregroundStyle(StrandPalette.textTertiary)
            }
            .padding(8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func setDay(_ i: Int, _ id: String) {
        store.update { $0.plan[i] = id }
    }
}

// MARK: - Library

struct FitWorkoutLibraryView: View {
    @ObservedObject private var store = FitStore.shared
    @State private var preview: FitTemplate?
    @State private var editing: FitTemplateEditor.Target?

    var body: some View {
        ScreenScaffold(title: "My workouts", subtitle: "Tap one to preview or start it") {
            HStack {
                SectionHeader("Your own")
                Spacer()
                FitRoundIconButton(symbol: "plus", label: "New workout") { editing = .new }
            }
            if store.data.templates.isEmpty {
                NoopCard {
                    VStack(spacing: 12) {
                        FitIconTile(symbol: "plus", size: 56)
                        Text("Build your own workout").font(StrandFont.headline)
                        Text("Pick exercises, set your sets and reps, and it becomes an option every day.")
                            .font(StrandFont.subhead).foregroundStyle(StrandPalette.textSecondary)
                            .multilineTextAlignment(.center)
                        FitPrimaryButton(title: "Create workout") { editing = .new }
                    }
                    .frame(maxWidth: .infinity)
                }
            } else {
                templateList(store.data.templates)
            }
            SectionHeader("Day options")
            templateList(FitCatalog.templates)
        }
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $preview) { FitTemplatePreview(template: $0) }
        .sheet(item: $editing) { FitTemplateEditor(target: $0) }
    }

    private func templateList(_ templates: [FitTemplate]) -> some View {
        NoopCard(padding: 8) {
            VStack(spacing: 0) {
                ForEach(Array(templates.enumerated()), id: \.element.id) { index, t in
                    Button { preview = t } label: {
                        FitNavRow(symbol: "dumbbell.fill", title: t.name,
                                  subtitle: "\(t.muscleText) · \(t.items.count) exercises")
                            .padding(8)
                    }
                    .buttonStyle(.plain)
                    if index < templates.count - 1 {
                        Divider().overlay(StrandPalette.hairline).padding(.leading, 64)
                    }
                }
            }
        }
    }
}

// MARK: - Preview

struct FitTemplatePreview: View {
    private let original: FitTemplate
    @ObservedObject private var store = FitStore.shared

    init(template: FitTemplate) { original = template }

    /// Re-read from the store so the sheet reflects an Edit → Save made from it.
    private var template: FitTemplate { store.template(original.id) ?? original }
    @Environment(\.dismiss) private var dismiss
    @State private var editing: FitTemplateEditor.Target?
    @State private var confirmReplace = false
    @State private var confirmDelete = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("\(template.muscleText) · \(template.items.count) exercises · ~\(template.estimatedMinutes) min")
                        .font(StrandFont.subhead).foregroundStyle(StrandPalette.textSecondary)
                    NoopCard(padding: 8) {
                        VStack(spacing: 0) {
                            ForEach(Array(template.items.enumerated()), id: \.element.id) { index, item in
                                row(item)
                                if index < template.items.count - 1 {
                                    Divider().overlay(StrandPalette.hairline).padding(.leading, 64)
                                }
                            }
                        }
                    }
                    FitPrimaryButton(title: "Start workout", symbol: "play.fill") {
                        if store.data.active != nil { confirmReplace = true } else { start() }
                    }
                    HStack(spacing: 10) {
                        Button { editing = template.isBuiltin ? .copy(template) : .edit(template) } label: {
                            Label(template.isBuiltin ? "Copy & edit" : "Edit", systemImage: "pencil")
                                .frame(maxWidth: .infinity).frame(height: 46)
                                .background(Capsule().fill(StrandPalette.surfaceInset))
                        }
                        if !template.isBuiltin {
                            Button { confirmDelete = true } label: {
                                Image(systemName: "trash")
                                    .frame(width: 46, height: 46)
                                    .background(Circle().fill(StrandPalette.surfaceInset))
                            }
                            .foregroundStyle(StrandPalette.statusCritical)
                            .accessibilityLabel("Delete workout")
                        }
                    }
                    .font(StrandFont.headline)
                    .foregroundStyle(StrandPalette.textPrimary)
                    .buttonStyle(.plain)
                }
                .padding(NoopMetrics.screenHPadding)
            }
            .background(StrandPalette.surfaceBase.ignoresSafeArea())
            .navigationTitle(template.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            }
            .sheet(item: $editing) { FitTemplateEditor(target: $0) }
            .confirmationDialog("A workout is already in progress", isPresented: $confirmReplace,
                                titleVisibility: .visible) {
                Button("Resume current workout") {
                    dismiss()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { store.isSessionPresented = true }
                }
                Button("Discard it and start \(template.name)", role: .destructive) {
                    store.discardWorkout()
                    start()
                }
            }
            .confirmationDialog("Delete \(template.name)? Logged history stays.", isPresented: $confirmDelete,
                                titleVisibility: .visible) {
                Button("Delete workout", role: .destructive) {
                    store.deleteTemplate(template.id)
                    dismiss()
                }
            }
        }
    }

    private func row(_ item: FitTemplateItem) -> some View {
        let ex = store.exercise(item.exerciseID)
        let last = store.lastSets(for: item.exerciseID)?.first
        let suffix = ex.kind == .time ? "s" : (ex.kind == .cardio ? " min" : "")
        return HStack(spacing: 12) {
            FitIconTile(symbol: ex.symbol)
            VStack(alignment: .leading, spacing: 2) {
                Text(ex.name).font(StrandFont.headline).foregroundStyle(StrandPalette.textPrimary)
                Text(last.map { "Last: \(store.setText($0, kind: ex.kind))" } ?? ex.muscle.label)
                    .font(StrandFont.caption).foregroundStyle(StrandPalette.textTertiary)
            }
            Spacer(minLength: 0)
            Text("\(item.sets) × \(item.reps)\(suffix)")
                .font(StrandFont.captionNumber)
                .foregroundStyle(StrandPalette.textSecondary)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(Capsule().fill(StrandPalette.surfaceInset))
        }
        .padding(8)
    }

    /// The live-workout cover is presented by the tab root, so let this sheet finish dismissing first.
    private func start() {
        let t = template
        dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { store.startWorkout(t) }
    }
}

// MARK: - Editor

struct FitTemplateEditor: View {
    enum Target: Identifiable {
        case new
        case edit(FitTemplate)
        case copy(FitTemplate)

        var id: String {
            switch self {
            case .new: return "new"
            case .edit(let t): return "edit-\(t.id)"
            case .copy(let t): return "copy-\(t.id)"
            }
        }
    }

    let target: Target
    @ObservedObject private var store = FitStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var items: [FitTemplateItem] = []
    @State private var showPicker = false
    @State private var loaded = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("e.g. Heavy chest day", text: $name)
                        .textInputAutocapitalization(.sentences)
                }
                Section {
                    ForEach($items) { $item in
                        itemRow($item)
                    }
                    .onDelete { items.remove(atOffsets: $0) }
                    .onMove { items.move(fromOffsets: $0, toOffset: $1) }
                    Button { showPicker = true } label: { Label("Add exercise", systemImage: "plus.circle.fill") }
                } header: {
                    Text("Exercises")
                } footer: {
                    Text("Swipe left to remove. Use Edit to reorder.")
                }
            }
            .fitKeyboardDone()
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || items.isEmpty)
                }
                ToolbarItem(placement: .topBarLeading) { EditButton() }
            }
            .sheet(isPresented: $showPicker) {
                FitExercisePicker { id in
                    let p = FitCatalog.defaultPrescription(for: store.exercise(id).kind)
                    items.append(FitTemplateItem(exerciseID: id, sets: p.sets, reps: p.reps))
                    showPicker = false
                }
            }
            .onAppear(perform: load)
        }
    }

    private var title: String {
        switch target {
        case .new: return "New workout"
        case .edit: return "Edit workout"
        case .copy: return "Copy workout"
        }
    }

    private func itemRow(_ item: Binding<FitTemplateItem>) -> some View {
        let ex = store.exercise(item.wrappedValue.exerciseID)
        let unit = ex.kind == .time ? "sec" : (ex.kind == .cardio ? "min" : "reps")
        return VStack(alignment: .leading, spacing: 8) {
            Text(ex.name).font(StrandFont.headline)
            HStack {
                Stepper("\(item.wrappedValue.sets) sets", value: item.sets, in: 1...12)
                    .fixedSize()
                Spacer()
                TextField("10", value: item.reps, format: .number)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 56)
                Text(unit).foregroundStyle(StrandPalette.textTertiary)
            }
            .font(StrandFont.subhead)
        }
        .padding(.vertical, 4)
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        switch target {
        case .new:
            break
        case .edit(let t):
            name = t.name
            items = t.items
        case .copy(let t):
            name = "My \(t.name)"
            items = t.items.map { FitTemplateItem(exerciseID: $0.exerciseID, sets: $0.sets, reps: $0.reps) }
        }
    }

    private func save() {
        let trimmed = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(40))
        let cleaned = items.map { item -> FitTemplateItem in
            var copy = item
            copy.reps = min(999, max(1, copy.reps))
            return copy
        }
        var muscles: [FitMuscle] = []
        for item in cleaned {
            let m = store.exercise(item.exerciseID).muscle
            if !muscles.contains(m) { muscles.append(m) }
        }
        let id: String
        if case .edit(let t) = target { id = t.id } else { id = "c-\(UUID().uuidString.prefix(8))" }
        store.saveTemplate(FitTemplate(id: id, name: trimmed, muscles: muscles, items: cleaned))
        dismiss()
    }
}

// MARK: - Exercise picker

struct FitExercisePicker: View {
    let onPick: (String) -> Void
    @ObservedObject private var store = FitStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var muscle: FitMuscle?
    @State private var newName = ""
    @State private var newMuscle: FitMuscle = .chest
    @State private var newKind: FitExerciseKind = .weight

    private var results: [FitExercise] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        return store.allExercises
            .filter { (muscle == nil || $0.muscle == muscle) && (q.isEmpty || $0.name.lowercased().contains(q)) }
            .sorted { $0.name < $1.name }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            FitChip(title: "All", selected: muscle == nil) { muscle = nil }
                            ForEach(FitMuscle.allCases) { m in
                                FitChip(title: m.label, selected: muscle == m) { muscle = m }
                            }
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                }
                Section {
                    if results.isEmpty {
                        Text("No matches. Create it below.").foregroundStyle(StrandPalette.textTertiary)
                    }
                    ForEach(results) { ex in
                        Button { onPick(ex.id) } label: {
                            HStack(spacing: 12) {
                                FitIconTile(symbol: ex.symbol, size: 34)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(ex.name).foregroundStyle(StrandPalette.textPrimary)
                                    Text(ex.muscle.label).font(StrandFont.caption)
                                        .foregroundStyle(StrandPalette.textTertiary)
                                }
                                Spacer()
                                Image(systemName: "plus.circle.fill").foregroundStyle(StrandPalette.accent)
                            }
                        }
                    }
                }
                Section("Create custom exercise") {
                    TextField("Exercise name", text: $newName)
                    Picker("Muscle", selection: $newMuscle) {
                        ForEach(FitMuscle.allCases) { Text($0.label).tag($0) }
                    }
                    Picker("Type", selection: $newKind) {
                        Text("Weight × reps").tag(FitExerciseKind.weight)
                        Text("Timed hold").tag(FitExerciseKind.time)
                        Text("Distance / time").tag(FitExerciseKind.cardio)
                    }
                    Button("Create & add") {
                        let trimmed = String(newName.trimmingCharacters(in: .whitespacesAndNewlines).prefix(48))
                        let created = store.addCustomExercise(name: trimmed, muscle: newMuscle, kind: newKind)
                        onPick(created.id)
                    }
                    .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .searchable(text: $query, prompt: "Search exercises")
            .navigationTitle("Add exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            }
        }
    }
}
#endif
