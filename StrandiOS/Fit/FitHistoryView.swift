#if os(iOS)
import SwiftUI
import StrandDesign

/// Past workouts, workouts-per-week chart and personal bests.
struct FitHistoryView: View {
    @ObservedObject private var store = FitStore.shared
    @State private var detail: FitSession?

    private static let weeksShown = 12
    private static let topRecords = 6

    var body: some View {
        let now = Date()
        let last30 = store.sessions(since: FitStore.addDays(-29, to: FitStore.calendar.startOfDay(for: now))).count
        let bests: [FitRecord] = store.personalBests(in: store.data.sessions)
            .sorted { $0.value.date > $1.value.date }
            .prefix(Self.topRecords)
            .map { FitRecord(exerciseID: $0.key, name: store.exercise($0.key).name, weight: $0.value.weight, reps: $0.value.reps) }

        ScreenScaffold(title: "History", subtitle: "\(last30) workouts in the last 30 days", lazy: true) {
            weeklyCard(now: now)
            if !bests.isEmpty {
                NoopCard {
                    VStack(alignment: .leading, spacing: 10) {
                        FitCardLabel(title: "Personal bests", symbol: "trophy.fill")
                        ForEach(bests) { record in
                            HStack {
                                Text(record.name).font(StrandFont.subhead)
                                Spacer()
                                Text("\(FitFormat.number(record.weight)) \(store.weightUnit) × \(record.reps)")
                                    .font(StrandFont.bodyNumber)
                            }
                        }
                    }
                }
            }
            SectionHeader("Sessions")
            if store.data.sessions.isEmpty {
                NoopCard {
                    Text("No workouts yet. Finish one and it lands here.")
                        .font(StrandFont.subhead).foregroundStyle(StrandPalette.textSecondary)
                }
            }
            ForEach(store.data.sessions) { s in
                Button { detail = s } label: { sessionRow(s) }
                    .buttonStyle(.plain)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $detail) { FitSessionDetail(session: $0) }
    }

    private func weeklyCard(now: Date) -> some View {
        let thisWeek = FitStore.startOfWeek(now)
        let counts = (0..<Self.weeksShown).map { i in
            store.sessionCount(inWeekStarting: FitStore.addDays(-7 * (Self.weeksShown - 1 - i), to: thisWeek))
        }
        let maxCount = Double(max(4, counts.max() ?? 0))
        return NoopCard {
            VStack(alignment: .leading, spacing: 12) {
                FitCardLabel(title: "Workouts per week", symbol: "calendar", trailing: "last \(Self.weeksShown) weeks")
                HStack(alignment: .bottom, spacing: 2) {
                    ForEach(Array(counts.enumerated()), id: \.offset) { i, n in
                        FitColumn(fraction: Double(n) / maxCount, tint: StrandPalette.statusPositive,
                                  valueText: n > 0 ? "\(n)" : " ", label: "", height: 80,
                                  highlighted: i == Self.weeksShown - 1)
                    }
                }
            }
        }
    }

    private func sessionRow(_ s: FitSession) -> some View {
        let muscles = Array(Set(s.exercises.map { store.exercise($0.exerciseID).muscle }))
            .sorted { $0.label < $1.label }
            .prefix(3)
            .map(\.label)
            .joined(separator: " · ")
        return NoopCard(padding: 12) {
            HStack(spacing: 12) {
                VStack(spacing: 0) {
                    Text(s.start.formatted(.dateTime.month(.abbreviated)).uppercased()).font(StrandFont.overline)
                    Text(s.start.formatted(.dateTime.day())).font(StrandFont.headline)
                }
                .foregroundStyle(StrandPalette.textPrimary)
                .frame(width: 44, height: 48)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(StrandPalette.surfaceInset))
                VStack(alignment: .leading, spacing: 2) {
                    Text(s.name).font(StrandFont.headline).foregroundStyle(StrandPalette.textPrimary)
                    Text("\(FitFormat.minutes(s.duration)) · \(s.setCount) sets · \(FitFormat.whole(store.volume(of: s))) \(store.weightUnit)")
                        .font(StrandFont.caption).foregroundStyle(StrandPalette.textSecondary)
                    if !muscles.isEmpty {
                        Text(muscles).font(StrandFont.caption).foregroundStyle(StrandPalette.textTertiary)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(StrandFont.footnote)
                    .foregroundStyle(StrandPalette.textTertiary)
            }
        }
    }
}

struct FitSessionDetail: View {
    let session: FitSession
    @ObservedObject private var store = FitStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var confirmDelete = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(session.start.formatted(date: .complete, time: .shortened))
                        .font(StrandFont.subhead).foregroundStyle(StrandPalette.textSecondary)
                    HStack(spacing: 10) {
                        tile(FitFormat.minutes(session.duration), "time")
                        tile("\(session.setCount)", "sets")
                        tile(FitFormat.whole(store.volume(of: session)), store.weightUnit)
                    }
                    ForEach(session.exercises) { e in
                        let ex = store.exercise(e.exerciseID)
                        NoopCard(padding: 14) {
                            VStack(alignment: .leading, spacing: 10) {
                                Text(ex.name).font(StrandFont.headline)
                                ForEach(Array(e.sets.enumerated()), id: \.element.id) { i, set in
                                    HStack {
                                        Text("Set \(i + 1)").foregroundStyle(StrandPalette.textTertiary)
                                        Spacer()
                                        Text(store.setText(set, kind: ex.kind))
                                    }
                                    .font(StrandFont.subhead)
                                }
                            }
                        }
                    }
                    Button(role: .destructive) { confirmDelete = true } label: {
                        Label("Delete workout", systemImage: "trash")
                            .font(StrandFont.headline)
                            .frame(maxWidth: .infinity).frame(height: 48)
                            .background(Capsule().fill(StrandPalette.surfaceInset))
                    }
                    .foregroundStyle(StrandPalette.statusCritical)
                    .buttonStyle(.plain)
                }
                .padding(NoopMetrics.screenHPadding)
            }
            .background(StrandPalette.surfaceBase.ignoresSafeArea())
            .navigationTitle(session.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .confirmationDialog("Delete this workout from your history?", isPresented: $confirmDelete,
                                titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    store.deleteSession(session.id)
                    dismiss()
                }
            }
        }
    }

    private func tile(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(StrandFont.number(20, weight: .regular))
            Text(label).font(StrandFont.caption).foregroundStyle(StrandPalette.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(StrandPalette.surfaceRaised))
    }
}
#endif
