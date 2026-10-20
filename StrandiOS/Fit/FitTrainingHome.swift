#if os(iOS)
import SwiftUI
import StrandDesign

/// Workouts half of the Fit tab: weekly progress, today's planned workout, other day options,
/// stats, muscle balance, and links to the plan / library / history screens.
struct FitTrainingHome: View {
    @ObservedObject private var store = FitStore.shared
    @State private var preview: FitTemplate?
    @State private var balanceRange = 14

    private static let barDays = 28
    private static let ranges = [7, 14, 30]

    var body: some View {
        let now = Date()
        VStack(alignment: .leading, spacing: 16) {
            if let active = store.data.active { resumeBanner(active) }
            heroCard(now: now)
            planCard(now: now)
            HStack(spacing: 12) {
                statCard(title: "Week volume", symbol: "scalemass.fill",
                         value: FitFormat.whole(weekVolume(now: now)), unit: store.weightUnit)
                let streak = store.weekStreak(now: now)
                statCard(title: "Week streak", symbol: "flame.fill",
                         value: "\(streak)", unit: streak == 1 ? "week" : "weeks")
            }
            optionsCard(now: now)
            balanceCard(now: now)
            linksCard
        }
        .sheet(item: $preview) { FitTemplatePreview(template: $0) }
    }

    // MARK: Sections

    private func resumeBanner(_ active: FitSession) -> some View {
        Button { store.isSessionPresented = true } label: {
            HStack(spacing: 12) {
                Circle().fill(StrandPalette.statusPositive).frame(width: 10, height: 10)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(active.name) in progress").font(StrandFont.headline)
                    TimelineView(.periodic(from: .now, by: 1)) { ctx in
                        Text(FitFormat.clock(ctx.date.timeIntervalSince(active.start)))
                            .font(StrandFont.captionNumber)
                            .opacity(0.7)
                    }
                }
                Spacer(minLength: 0)
                Text("Resume").font(StrandFont.subhead)
                Image(systemName: "chevron.right").font(StrandFont.footnote)
            }
            .foregroundStyle(StrandPalette.surfaceRaised)
            .padding(16)
            .background(RoundedRectangle(cornerRadius: NoopMetrics.cardRadius, style: .continuous)
                .fill(StrandPalette.textPrimary))
        }
        .buttonStyle(.plain)
    }

    private func heroCard(now: Date) -> some View {
        let week = store.sessions(since: FitStore.startOfWeek(now)).count
        let goal = store.data.settings.weeklyGoal
        let status = paceStatus(done: week, goal: goal, now: now)
        let trained = store.trainedDays
        let today = FitStore.calendar.startOfDay(for: now)
        let filled = (0..<Self.barDays).map { i in
            trained.contains(FitStore.addDays(i - (Self.barDays - 1), to: today))
        }
        return NoopCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    FitBigNumber(value: "\(week)", unit: "/\(goal)", size: 64)
                    Spacer()
                    VStack(alignment: .trailing, spacing: 6) {
                        FitStatusDot(text: status.text, color: status.color)
                        Text(now.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                            .font(StrandFont.caption)
                            .foregroundStyle(StrandPalette.textTertiary)
                    }
                    .padding(.top, 10)
                }
                Text("workouts this week").font(StrandFont.subhead).foregroundStyle(StrandPalette.textSecondary)
                FitPillBars(filled: filled).padding(.top, 4)
                HStack {
                    Text("4 weeks ago")
                    Spacer()
                    Text("Today")
                }
                .font(StrandFont.caption)
                .foregroundStyle(StrandPalette.textTertiary)
            }
        }
    }

    @ViewBuilder
    private func planCard(now: Date) -> some View {
        let dayName = FitCatalog.weekdaysLong[FitStore.weekdayIndex(now)]
        if let t = store.templateForToday(now) {
            let doneToday = store.sessions(since: FitStore.calendar.startOfDay(for: now))
                .contains { $0.templateID == t.id }
            NoopCard {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        FitCardLabel(title: "\(dayName) · Planned", symbol: "calendar")
                        if doneToday { FitStatusDot(text: "Done", color: StrandPalette.statusPositive) }
                    }
                    Text(t.name).font(StrandFont.rounded(30, weight: .regular))
                        .foregroundStyle(StrandPalette.textPrimary)
                    muscleTags(t.muscles)
                    Text("\(t.items.count) exercises · ~\(t.estimatedMinutes) min")
                        .font(StrandFont.footnote).foregroundStyle(StrandPalette.textTertiary)
                    HStack(spacing: 10) {
                        FitPrimaryButton(title: "Start \(t.name)", symbol: "play.fill") { start(t) }
                        Button { preview = t } label: {
                            Image(systemName: "list.bullet")
                                .font(StrandFont.headline)
                                .foregroundStyle(StrandPalette.textPrimary)
                                .frame(width: 50, height: 50)
                                .background(Circle().fill(StrandPalette.surfaceInset))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Preview \(t.name)")
                    }
                }
            }
        } else {
            NoopCard {
                VStack(alignment: .leading, spacing: 10) {
                    FitCardLabel(title: "\(dayName) · Rest day", symbol: "moon.zzz.fill")
                    Text("Recover").font(StrandFont.rounded(30, weight: .regular))
                        .foregroundStyle(StrandPalette.textPrimary)
                    Text("Nothing planned today. Fancy something light? Pick an option below, or start a blank workout.")
                        .font(StrandFont.subhead).foregroundStyle(StrandPalette.textSecondary)
                    Button("Start a blank workout") { startBlank() }
                        .font(StrandFont.headline)
                        .foregroundStyle(StrandPalette.accent)
                }
            }
        }
    }

    private func statCard(title: String, symbol: String, value: String, unit: String) -> some View {
        NoopCard {
            VStack(alignment: .leading, spacing: 8) {
                FitCardLabel(title: title, symbol: symbol)
                FitBigNumber(value: value, unit: unit, size: 32)
            }
        }
    }

    private func optionsCard(now: Date) -> some View {
        let plannedID = store.data.plan[FitStore.weekdayIndex(now)]
        let pick = store.suggestedTemplate(excluding: plannedID)
        return NoopCard {
            VStack(alignment: .leading, spacing: 12) {
                FitCardLabel(title: "Other options today", symbol: "square.stack.3d.up.fill")
                if let pick {
                    Button { preview = pick.template } label: {
                        HStack(spacing: 12) {
                            FitIconTile(symbol: "sparkles", tint: StrandPalette.statusPositive)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Suggested: \(pick.template.name)").font(StrandFont.headline)
                                    .foregroundStyle(StrandPalette.textPrimary)
                                Text(pick.daysSince.map { "last trained \($0)d ago" } ?? "not trained yet")
                                    .font(StrandFont.caption).foregroundStyle(StrandPalette.textTertiary)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right").font(StrandFont.footnote)
                                .foregroundStyle(StrandPalette.textTertiary)
                        }
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(StrandPalette.statusPositive.opacity(0.12)))
                    }
                    .buttonStyle(.plain)
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(store.allTemplates) { t in
                            FitChip(title: t.name, selected: t.id == plannedID) { preview = t }
                        }
                    }
                }
            }
        }
    }

    private func balanceCard(now: Date) -> some View {
        let sets = store.muscleSets(lastDays: balanceRange, now: now)
        let muscles = FitMuscle.allCases.filter { $0 != .cardio }
        let total = sets.values.reduce(0, +)
        return NoopCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    FitCardLabel(title: "Muscle balance", symbol: "figure.strengthtraining.traditional")
                    FitStatusDot(text: "On target", color: StrandPalette.statusPositive)
                    FitStatusDot(text: "Low", color: StrandPalette.statusWarning)
                }
                FitBigNumber(value: "\(total)", unit: "sets", size: 32)
                HStack(alignment: .bottom, spacing: 4) {
                    ForEach(muscles) { m in
                        let n = sets[m] ?? 0
                        let target = m.weeklySetTarget * Double(balanceRange) / 7
                        let fraction = Double(n) / target
                        FitColumn(fraction: n == 0 ? 0 : max(0.08, fraction),
                                  tint: fraction >= 0.6 ? StrandPalette.statusPositive : StrandPalette.statusWarning,
                                  valueText: "\(n)",
                                  label: String(m.label.prefix(3)))
                    }
                }
                SegmentedPillControl(Self.ranges, selection: $balanceRange) { "\($0)d" }
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var linksCard: some View {
        NoopCard {
            VStack(spacing: 4) {
                NavigationLink(value: FitRoute.plan) {
                    FitNavRow(symbol: "calendar", title: "Weekly plan",
                              subtitle: "Choose a split or set each day")
                }
                Divider().overlay(StrandPalette.hairline)
                NavigationLink(value: FitRoute.library) {
                    FitNavRow(symbol: "dumbbell.fill", title: "My workouts",
                              subtitle: "\(store.data.templates.count) of your own · \(FitCatalog.templates.count) ready-made")
                }
                Divider().overlay(StrandPalette.hairline)
                NavigationLink(value: FitRoute.history) {
                    FitNavRow(symbol: "clock.arrow.circlepath", title: "History",
                              subtitle: "\(store.data.sessions.count) workouts logged")
                }
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: Helpers

    private func muscleTags(_ muscles: [FitMuscle]) -> some View {
        HStack(spacing: 6) {
            ForEach(muscles) { m in
                Text(m.label)
                    .font(StrandFont.caption)
                    .foregroundStyle(StrandPalette.textSecondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(StrandPalette.surfaceInset))
            }
        }
    }

    private func paceStatus(done: Int, goal: Int, now: Date) -> (text: String, color: Color) {
        if done >= goal { return ("Goal hit", StrandPalette.statusPositive) }
        let expected = (goal * (FitStore.weekdayIndex(now) + 1)) / 7
        return done >= expected ? ("On track", StrandPalette.statusPositive) : ("Behind", StrandPalette.statusWarning)
    }

    private func weekVolume(now: Date) -> Double {
        store.sessions(since: FitStore.startOfWeek(now)).reduce(0) { $0 + store.volume(of: $1) }
    }

    private func start(_ template: FitTemplate) {
        if store.data.active != nil {
            store.isSessionPresented = true
        } else {
            store.startWorkout(template)
        }
    }

    private func startBlank() {
        if store.data.active != nil {
            store.isSessionPresented = true
        } else {
            store.startEmptyWorkout()
        }
    }
}
#endif
