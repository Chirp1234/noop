#if os(iOS)
import SwiftUI
import UIKit
import UniformTypeIdentifiers
import StrandDesign

/// The Fit tab: a workout planner/logger and a food & calorie tracker, both stored on-device.
/// Takes the tab slot Coach used to hold; Coach itself moved to the More list.
struct FitView: View {
    enum Pane: String, CaseIterable, Hashable {
        case training, food
        var label: String { self == .training ? "Workouts" : "Food" }
    }

    @ObservedObject private var store = FitStore.shared
    @AppStorage("noop.fit.section") private var sectionRaw = Pane.training.rawValue
    @State private var showSettings = false

    private var section: Binding<Pane> {
        Binding(get: { Pane(rawValue: sectionRaw) ?? .training }, set: { sectionRaw = $0.rawValue })
    }

    var body: some View {
        ScreenScaffold(title: "Fit",
                       subtitle: "Train and fuel, all on this phone",
                       topBackground: liquidScaffoldSky()) {
            HStack(spacing: 10) {
                SegmentedPillControl(Pane.allCases, selection: section, fillsAvailableWidth: true) { $0.label }
                FitRoundIconButton(symbol: "slider.horizontal.3", label: "Fit settings") { showSettings = true }
            }
            if store.lastSaveFailed {
                Label("Couldn't save your last change. Is the phone out of storage?", systemImage: "exclamationmark.triangle.fill")
                    .font(StrandFont.footnote)
                    .foregroundStyle(StrandPalette.statusCritical)
            }
            switch section.wrappedValue {
            case .training: FitTrainingHome()
            case .food: FitFoodHome()
            }
        }
        // First-hop pushes ride the tab's NavigationPath as values (see TabRoute.swift), so a re-tap of
        // the Fit tab pops back to this root and the tab-swipe gesture stands down on sub-screens.
        .navigationDestination(for: FitRoute.self) { route in
            switch route {
            case .plan: FitPlanView()
            case .library: FitWorkoutLibraryView()
            case .history: FitHistoryView()
            }
        }
        .sheet(isPresented: $showSettings) { FitSettingsSheet() }
        .fullScreenCover(isPresented: $store.isSessionPresented) { FitSessionView() }
    }
}

/// First-hop destinations pushed from the Fit tab root.
enum FitRoute: Hashable {
    case plan, library, history
}

struct FitRoundIconButton: View {
    let symbol: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(StrandFont.headline)
                .foregroundStyle(StrandPalette.textPrimary)
                .frame(width: 44, height: 44)
                .background(Circle().fill(StrandPalette.surfaceRaised))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(label))
    }
}

/// Adds a keyboard Done button to number-pad forms (number pads have no Return key, and a
/// `TextField(value:format:)` only writes its binding once editing ends).
struct FitKeyboardDone: ViewModifier {
    func body(content: Content) -> some View {
        content
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                                        to: nil, from: nil, for: nil)
                    }
                }
            }
    }
}

extension View {
    func fitKeyboardDone() -> some View { modifier(FitKeyboardDone()) }
}

// MARK: - Settings

struct FitSettingsSheet: View {
    @ObservedObject private var store = FitStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var exportURL: URL?
    @State private var showImporter = false
    @State private var confirmErase = false
    @State private var message: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Workouts") {
                    Picker("Weight unit", selection: Binding(
                        get: { store.data.settings.useKilograms },
                        set: { v in store.update { $0.settings.useKilograms = v } })) {
                        Text("kg").tag(true)
                        Text("lb").tag(false)
                    }
                    .pickerStyle(.segmented)
                    Stepper(value: Binding(get: { store.data.settings.restSeconds },
                                           set: { v in store.update { $0.settings.restSeconds = v } }),
                            in: 15...600, step: 15) {
                        Text("Rest timer: \(store.data.settings.restSeconds)s")
                    }
                    Stepper(value: Binding(get: { store.data.settings.weeklyGoal },
                                           set: { v in store.update { $0.settings.weeklyGoal = v } }),
                            in: 1...7) {
                        Text("Weekly goal: \(store.data.settings.weeklyGoal) workouts")
                    }
                }
                Section {
                    if let exportURL {
                        ShareLink(item: exportURL) { Label("Export backup", systemImage: "square.and.arrow.up") }
                    }
                    Button { showImporter = true } label: {
                        Label("Import backup", systemImage: "square.and.arrow.down")
                    }
                    Button(role: .destructive) { confirmErase = true } label: {
                        Label("Erase all Fit data", systemImage: "trash")
                    }
                } header: {
                    Text("Your data")
                } footer: {
                    Text("Workouts and food logs are stored only on this iPhone, separate from strap data. Export a backup now and then.")
                }
                if let message {
                    Section { Text(message).font(StrandFont.footnote) }
                }
            }
            .navigationTitle("Fit settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .task(id: store.data.sessions.count + store.data.foodLog.count + store.data.templates.count) {
                exportURL = try? store.exportBackup()
            }
            .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json]) { result in
                switch result {
                case .success(let url):
                    do {
                        try store.importBackup(from: url)
                        exportURL = try? store.exportBackup()
                        message = "Backup restored."
                    } catch {
                        message = "That file isn't a valid Fit backup."
                    }
                case .failure:
                    message = "Couldn't open that file."
                }
            }
            .confirmationDialog("Erase every workout, template and food entry?", isPresented: $confirmErase,
                                titleVisibility: .visible) {
                Button("Erase all", role: .destructive) {
                    store.eraseAll()
                    message = "All Fit data erased."
                }
            }
        }
    }
}

// MARK: - Shared pieces

/// Big light numeral with a small unit, the hero idiom of the Fit screens.
struct FitBigNumber: View {
    let value: String
    var unit: String? = nil
    var size: CGFloat = 56

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(value)
                .font(StrandFont.number(size, weight: .light))
                .foregroundStyle(StrandPalette.textPrimary)
                .contentTransition(.numericText())
            if let unit {
                Text(unit)
                    .font(StrandFont.headline)
                    .foregroundStyle(StrandPalette.textTertiary)
            }
        }
    }
}

struct FitStatusDot: View {
    let text: String
    let color: Color

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(text).font(StrandFont.footnote).foregroundStyle(StrandPalette.textSecondary)
        }
    }
}

struct FitCardLabel: View {
    let title: String
    let symbol: String
    var trailing: String? = nil

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(StrandFont.footnote)
                .foregroundStyle(StrandPalette.textTertiary)
            Text(title).font(StrandFont.subhead).foregroundStyle(StrandPalette.textSecondary)
            Spacer(minLength: 0)
            if let trailing {
                Text(trailing).font(StrandFont.caption).foregroundStyle(StrandPalette.textTertiary)
            }
        }
    }
}

struct FitIconTile: View {
    let symbol: String
    var tint: Color = StrandPalette.textSecondary
    var size: CGFloat = 40

    var body: some View {
        Image(systemName: symbol)
            .font(StrandFont.rounded(size * 0.42, weight: .medium))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
                .fill(StrandPalette.surfaceInset))
    }
}

/// A row of thin vertical pills, one per day (filled = trained).
struct FitPillBars: View {
    let filled: [Bool]
    var tint: Color = StrandPalette.statusPositive
    var height: CGFloat = 44

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(filled.enumerated()), id: \.offset) { index, on in
                Capsule()
                    .fill(on ? tint : StrandPalette.surfaceInset)
                    .overlay {
                        if index == filled.count - 1 {
                            Capsule().strokeBorder(StrandPalette.textPrimary, lineWidth: 1.5)
                        }
                    }
            }
        }
        .frame(height: height)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(filled.filter { $0 }.count) of the last \(filled.count) days trained")
    }
}

/// One vertical track with a proportional fill, used by the column charts.
struct FitColumn: View {
    let fraction: Double
    let tint: Color
    let valueText: String
    let label: String
    var height: CGFloat = 110
    var highlighted = false

    var body: some View {
        VStack(spacing: 6) {
            ZStack(alignment: .bottom) {
                Capsule().fill(StrandPalette.surfaceInset)
                Capsule()
                    .fill(tint)
                    .frame(height: height * CGFloat(min(1, max(0, fraction))))
                    .overlay {
                        if highlighted { Capsule().strokeBorder(StrandPalette.textPrimary, lineWidth: 1.5) }
                    }
            }
            .frame(width: 10, height: height)
            Text(valueText)
                .font(StrandFont.captionNumber)
                .foregroundStyle(StrandPalette.textSecondary)
            Text(label)
                .font(StrandFont.caption)
                .foregroundStyle(StrandPalette.textTertiary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }
}

struct FitChip: View {
    let title: String
    var selected = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(StrandFont.subhead)
                .foregroundStyle(selected ? StrandPalette.surfaceRaised : StrandPalette.textPrimary)
                .padding(.horizontal, 14)
                .frame(height: 36)
                .background(Capsule().fill(selected ? StrandPalette.textPrimary : StrandPalette.surfaceInset))
        }
        .buttonStyle(.plain)
    }
}

/// Full-width primary action in the Fit screens.
struct FitPrimaryButton: View {
    let title: String
    var symbol: String? = nil
    var tint: Color = StrandPalette.textPrimary
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let symbol { Image(systemName: symbol) }
                Text(title).font(StrandFont.headline)
            }
            .foregroundStyle(StrandPalette.surfaceRaised)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(Capsule().fill(tint))
        }
        .buttonStyle(.plain)
    }
}

/// A list row with an icon tile, title, subtitle and a trailing chevron.
struct FitNavRow: View {
    let symbol: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 12) {
            FitIconTile(symbol: symbol)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(StrandFont.headline).foregroundStyle(StrandPalette.textPrimary)
                Text(subtitle).font(StrandFont.caption).foregroundStyle(StrandPalette.textTertiary).lineLimit(1)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(StrandFont.footnote)
                .foregroundStyle(StrandPalette.textTertiary)
        }
        .contentShape(Rectangle())
    }
}
#endif
