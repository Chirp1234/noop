#if os(iOS)
import SwiftUI
import UIKit
import StrandDesign

/// Full-screen live workout: tick off sets, edit load/reps, rest timer, finish & save.
struct FitSessionView: View {
    private struct FieldID: Hashable {
        let exercise: Int
        let set: Int
        let isLoad: Bool
    }

    @ObservedObject private var store = FitStore.shared
    @State private var restEnd: Date?
    @State private var restToken = UUID()
    @State private var summary: FitFinishSummary?
    @State private var showPicker = false
    @State private var confirmFinish = false
    @State private var confirmDiscard = false
    @State private var nothingTicked = false
    @FocusState private var focused: FieldID?

    var body: some View {
        NavigationStack {
            Group {
                if let summary {
                    summaryView(summary)
                } else if let active = store.data.active {
                    sessionContent(active)
                } else {
                    VStack(spacing: 16) {
                        Text("No workout in progress").font(StrandFont.headline)
                        FitPrimaryButton(title: "Close") { store.isSessionPresented = false }
                            .frame(maxWidth: 220)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .background(StrandPalette.surfaceBase.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .sheet(isPresented: $showPicker) {
                FitExercisePicker { id in
                    store.addExerciseToActive(id)
                    showPicker = false
                }
            }
            .confirmationDialog("Finish and save this workout?", isPresented: $confirmFinish,
                                titleVisibility: .visible) {
                Button("Finish & save") { finish() }
            } message: {
                Text("Only ticked sets are saved.")
            }
            .confirmationDialog("Discard this workout? Nothing will be saved.", isPresented: $confirmDiscard,
                                titleVisibility: .visible) {
                Button("Discard workout", role: .destructive) { store.discardWorkout() }
            }
            .alert("No sets ticked yet", isPresented: $nothingTicked) {
                Button("Keep going", role: .cancel) {}
                Button("Discard workout", role: .destructive) { store.discardWorkout() }
            } message: {
                Text("Tick the sets you've done, then finish.")
            }
        }
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if summary == nil {
            ToolbarItem(placement: .topBarLeading) {
                Button { store.isSessionPresented = false } label: {
                    Image(systemName: "chevron.down")
                }
                .accessibilityLabel("Minimise workout")
            }
            ToolbarItem(placement: .principal) {
                Text(store.data.active?.name ?? "Workout").font(StrandFont.headline)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { showPicker = true } label: { Label("Add exercise", systemImage: "plus") }
                    Button(role: .destructive) { confirmDiscard = true } label: {
                        Label("Discard workout", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { focused = nil }
            }
        }
    }

    // MARK: Session

    private func sessionContent(_ active: FitSession) -> some View {
        let total = active.setCount
        let done = active.doneSetCount
        let progress = total == 0 ? 0 : Double(done) / Double(total)
        return ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    ProgressView(value: progress).tint(StrandPalette.statusPositive)
                    Text("\(Int(progress * 100))%").font(StrandFont.captionNumber)
                        .foregroundStyle(StrandPalette.textTertiary)
                }
                TimelineView(.periodic(from: .now, by: 1)) { ctx in
                    FitBigNumber(value: FitFormat.clock(ctx.date.timeIntervalSince(active.start)), size: 52)
                }
                Text("\(active.exercises.count) exercises · \(done) sets done")
                    .font(StrandFont.subhead).foregroundStyle(StrandPalette.textSecondary)
                ForEach(Array(active.exercises.enumerated()), id: \.element.id) { index, item in
                    exerciseCard(item, index: index, count: active.exercises.count)
                }
                Button { showPicker = true } label: {
                    Label("Add exercise", systemImage: "plus")
                        .font(StrandFont.headline)
                        .foregroundStyle(StrandPalette.textPrimary)
                        .frame(maxWidth: .infinity).frame(height: 50)
                        .background(Capsule().fill(StrandPalette.surfaceInset))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, NoopMetrics.screenHPadding)
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom) { dock }
    }

    private func exerciseCard(_ item: FitSessionExercise, index e: Int, count: Int) -> some View {
        let ex = store.exercise(item.exerciseID)
        let labels = ex.columnLabels(useKilograms: store.data.settings.useKilograms)
        let previous = store.lastSets(for: item.exerciseID) ?? []
        let complete = !item.sets.isEmpty && item.sets.allSatisfy(\.done)
        return NoopCard(padding: 12, tint: complete ? StrandPalette.statusPositive : nil) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 12) {
                    FitIconTile(symbol: ex.symbol)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(ex.name).font(StrandFont.headline).foregroundStyle(StrandPalette.textPrimary)
                        Text(ex.muscle.label).font(StrandFont.caption).foregroundStyle(StrandPalette.textTertiary)
                    }
                    Spacer(minLength: 0)
                    Menu {
                        if e > 0 {
                            Button { store.moveActiveExercise(from: e, by: -1) } label: {
                                Label("Move up", systemImage: "arrow.up")
                            }
                        }
                        if e < count - 1 {
                            Button { store.moveActiveExercise(from: e, by: 1) } label: {
                                Label("Move down", systemImage: "arrow.down")
                            }
                        }
                        Button(role: .destructive) { store.removeActiveExercise(e) } label: {
                            Label("Remove exercise", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .foregroundStyle(StrandPalette.textTertiary)
                            .frame(width: 36, height: 36)
                    }
                }
                HStack(spacing: 6) {
                    Text("SET").frame(width: 28)
                    Text("PREVIOUS").frame(maxWidth: .infinity, alignment: .leading)
                    Text(labels.0.uppercased()).frame(width: 72)
                    Text(labels.1.uppercased()).frame(width: 60)
                    Color.clear.frame(width: 40, height: 1)
                }
                .font(StrandFont.overline)
                .foregroundStyle(StrandPalette.textTertiary)
                ForEach(Array(item.sets.enumerated()), id: \.element.id) { s, set in
                    setRow(set, exercise: e, index: s, kind: ex.kind,
                           previous: s < previous.count ? previous[s] : nil)
                }
                HStack {
                    Button { store.addSet(exercise: e) } label: {
                        Label("Add set", systemImage: "plus")
                    }
                    .foregroundStyle(StrandPalette.statusPositive)
                    Spacer()
                    if item.sets.count > 1 {
                        Button { store.removeLastSet(exercise: e) } label: {
                            Label("Remove set", systemImage: "minus")
                        }
                        .foregroundStyle(StrandPalette.textTertiary)
                    }
                }
                .font(StrandFont.subhead)
                .buttonStyle(.plain)
                .padding(.top, 4)
            }
        }
    }

    private func setRow(_ set: FitSet, exercise e: Int, index s: Int, kind: FitExerciseKind,
                        previous: FitSet?) -> some View {
        let load = Binding<Double>(
            get: { store.data.active.flatMap { valueAt($0, e, s)?.weight } ?? 0 },
            set: { store.setWeight($0, exercise: e, set: s) })
        let reps = Binding<Int>(
            get: { store.data.active.flatMap { valueAt($0, e, s)?.reps } ?? 0 },
            set: { store.setReps($0, exercise: e, set: s) })
        return HStack(spacing: 6) {
            Text("\(s + 1)")
                .font(StrandFont.captionNumber)
                .foregroundStyle(StrandPalette.textTertiary)
                .frame(width: 28)
            Text(previous.map { store.setText($0, kind: kind) } ?? "—")
                .font(StrandFont.caption)
                .foregroundStyle(StrandPalette.textTertiary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            TextField("0", value: load, format: .number)
                .keyboardType(.decimalPad)
                .focused($focused, equals: FieldID(exercise: e, set: s, isLoad: true))
                .modifier(FitNumberField(width: 72, done: set.done))
            TextField("0", value: reps, format: .number)
                .keyboardType(.numberPad)
                .focused($focused, equals: FieldID(exercise: e, set: s, isLoad: false))
                .modifier(FitNumberField(width: 60, done: set.done))
            Button { toggle(exercise: e, set: s) } label: {
                Image(systemName: "checkmark")
                    .font(StrandFont.headline)
                    .foregroundStyle(set.done ? Color.white : StrandPalette.textTertiary)
                    .frame(width: 40, height: 40)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(set.done ? StrandPalette.statusPositive : StrandPalette.surfaceInset))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(set.done ? "Set \(s + 1) done" : "Mark set \(s + 1) done")
        }
        .padding(4)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(set.done ? StrandPalette.statusPositive.opacity(0.12) : Color.clear))
    }

    private func valueAt(_ a: FitSession, _ e: Int, _ s: Int) -> FitSet? {
        guard a.exercises.indices.contains(e), a.exercises[e].sets.indices.contains(s) else { return nil }
        return a.exercises[e].sets[s]
    }

    // MARK: Dock

    private var dock: some View {
        HStack(spacing: 12) {
            Button { toggleRest() } label: {
                HStack(spacing: 6) {
                    Image(systemName: "timer")
                    if let restEnd {
                        TimelineView(.periodic(from: .now, by: 1)) { ctx in
                            Text(FitFormat.clock(max(0, restEnd.timeIntervalSince(ctx.date))))
                                .monospacedDigit()
                        }
                    } else {
                        Text("Rest")
                    }
                }
                .font(StrandFont.subhead)
                .foregroundStyle(StrandPalette.textPrimary)
                .padding(.horizontal, 16)
                .frame(height: 48)
                .background(Capsule().fill(restEnd == nil ? StrandPalette.surfaceInset
                                                          : StrandPalette.statusWarning.opacity(0.25)))
            }
            .accessibilityLabel(restEnd == nil ? "Start rest timer" : "Stop rest timer")
            Button { confirmFinish = true } label: {
                HStack(spacing: 8) {
                    Image(systemName: "flag.checkered")
                    Text("Finish").font(StrandFont.headline)
                }
                .foregroundStyle(StrandPalette.surfaceRaised)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(Capsule().fill(StrandPalette.textPrimary))
            }
        }
        .buttonStyle(.plain)
        .padding(8)
        .background(Capsule().fill(.regularMaterial))
        .padding(.horizontal, NoopMetrics.screenHPadding)
        .padding(.bottom, 8)
    }

    // MARK: Actions

    private func toggle(exercise e: Int, set s: Int) {
        focused = nil
        if store.toggleSet(exercise: e, set: s) {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            startRest()
        }
    }

    private func toggleRest() {
        if restEnd == nil { startRest() } else { restEnd = nil; restToken = UUID() }
    }

    private func startRest() {
        let seconds = min(600, max(15, store.data.settings.restSeconds))
        let token = UUID()
        restToken = token
        restEnd = Date().addingTimeInterval(Double(seconds))
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(seconds) * 1_000_000_000)
            guard restToken == token else { return }
            restEnd = nil
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
    }

    private func finish() {
        focused = nil
        if let result = store.finishWorkout() {
            restEnd = nil
            restToken = UUID()
            summary = result
        } else {
            nothingTicked = true
        }
    }

    // MARK: Summary

    private func summaryView(_ summary: FitFinishSummary) -> some View {
        ScrollView {
            VStack(spacing: 16) {
                FitIconTile(symbol: "trophy.fill", tint: StrandPalette.statusPositive, size: 64)
                    .padding(.top, 32)
                Text("Workout saved").font(StrandFont.rounded(26, weight: .regular))
                Text(summary.session.name).font(StrandFont.subhead).foregroundStyle(StrandPalette.textSecondary)
                HStack(spacing: 10) {
                    summaryTile(FitFormat.minutes(summary.session.duration), "time")
                    summaryTile("\(summary.session.setCount)", "sets")
                    summaryTile(FitFormat.whole(summary.volume), store.weightUnit)
                }
                if !summary.records.isEmpty {
                    NoopCard {
                        VStack(alignment: .leading, spacing: 10) {
                            FitCardLabel(title: "New personal bests", symbol: "sparkles")
                            ForEach(summary.records) { r in
                                HStack {
                                    Text(r.name).font(StrandFont.subhead)
                                    Spacer()
                                    Text("\(FitFormat.number(r.weight)) \(store.weightUnit) × \(r.reps)")
                                        .font(StrandFont.bodyNumber)
                                }
                            }
                        }
                    }
                }
                FitPrimaryButton(title: "Done") { store.isSessionPresented = false }
                    .padding(.top, 8)
            }
            .padding(.horizontal, NoopMetrics.screenHPadding)
        }
    }

    private func summaryTile(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(StrandFont.number(20, weight: .regular))
            Text(label).font(StrandFont.caption).foregroundStyle(StrandPalette.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(StrandPalette.surfaceRaised))
    }
}

/// Inset numeric field used in the set rows.
private struct FitNumberField: ViewModifier {
    let width: CGFloat
    let done: Bool

    func body(content: Content) -> some View {
        content
            .multilineTextAlignment(.center)
            .font(StrandFont.bodyNumber)
            .frame(width: width, height: 40)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(done ? StrandPalette.surfaceRaised : StrandPalette.surfaceInset))
    }
}
#endif
