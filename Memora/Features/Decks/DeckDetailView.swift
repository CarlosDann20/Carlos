//
//  DeckDetailView.swift
//  Memora
//
//  The main panel for a selected deck: today's counts, a prominent study
//  button, next-due time, and quick actions (browse, options, stats, export).
//

import SwiftUI

struct DeckDetailView: View {
    @EnvironmentObject var env: AppEnvironment
    let deckID: Int64

    @State private var deck: Deck?
    @State private var counts = DeckCounts()
    @State private var showStudy = false
    @State private var studyAhead = false
    @State private var showBrowser = false
    @State private var showStats = false
    @State private var showOptions = false
    @State private var showExportDialog = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                countsRow
                studyButton
                quickActions
            }
            .padding(28)
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.background)
        .navigationTitle(deck?.leafName ?? "Mazo")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: reload)
        .onChange(of: env.dataVersion) { _, _ in reload() }
        .fullScreenCover(isPresented: $showStudy, onDismiss: reload) {
            StudyView(deckID: deckID, ignoreLimits: studyAhead)
        }
        .sheet(isPresented: $showBrowser) { CardBrowserView(deckID: deckID) }
        .sheet(isPresented: $showStats) { StatsView(deckID: deckID) }
        .sheet(isPresented: $showOptions) { DeckOptionsView(configID: deck?.configID ?? 1) }
        .confirmationDialog("Exportar mazo", isPresented: $showExportDialog, titleVisibility: .visible) {
            Button("Con historial y programación") { export(scheduling: true) }
            Button("Solo tarjetas (sin programación)") { export(scheduling: false) }
            Button("Cancelar", role: .cancel) {}
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(deck?.name ?? "")
                .font(.title2.weight(.bold))
                .foregroundStyle(Theme.textPrimary)
            HStack(spacing: 14) {
                Label("\(counts.total) tarjetas", systemImage: "rectangle.stack")
                if counts.suspended > 0 { Label("\(counts.suspended) suspendidas", systemImage: "pause.circle") }
                if let next = counts.nextDue, (counts.newCount + counts.learningCount + counts.reviewCount) == 0 {
                    Label("Próximo repaso: \(Self.relativeDue(next))", systemImage: "clock")
                }
            }
            .font(.subheadline)
            .foregroundStyle(Theme.textSecondary)
        }
    }

    private var countsRow: some View {
        HStack(spacing: 12) {
            StatTile(title: "Nuevas", value: counts.newCount, color: Theme.newCard)
            StatTile(title: "Aprendiendo", value: counts.learningCount, color: Theme.learnCard)
            StatTile(title: "Repaso", value: counts.reviewCount, color: Theme.reviewCard)
        }
    }

    private var dueTotal: Int { counts.newCount + counts.learningCount + counts.reviewCount }

    private var studyButton: some View {
        Button {
            studyAhead = dueTotal == 0
            showStudy = true
        } label: {
            HStack {
                Image(systemName: "play.fill")
                Text(dueTotal > 0 ? "Estudiar ahora (\(dueTotal))" : "Estudiar de todos modos (adelantar)")
                    .font(.headline)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .tint(dueTotal > 0 ? Theme.accent : Theme.surfaceElevated)
    }

    private var quickActions: some View {
        VStack(spacing: 10) {
            ActionRow(icon: "rectangle.stack", title: "Explorar tarjetas") { showBrowser = true }
            ActionRow(icon: "chart.bar", title: "Estadísticas del mazo") { showStats = true }
            ActionRow(icon: "slider.horizontal.3", title: "Opciones del mazo") { showOptions = true }
            ActionRow(icon: "square.and.arrow.up", title: "Exportar a .apkg") { showExportDialog = true }
        }
    }

    private func reload() {
        do {
            if let d = try env.store.deck(id: deckID) {
                deck = d
                counts = try env.store.deckCounts(for: d)
            }
        } catch { env.presentError(error) }
    }

    private func export(scheduling: Bool) {
        env.exportAPKG(deckIDs: [deckID], includeScheduling: scheduling, suggestedName: deck?.leafName ?? "mazo")
    }

    static func relativeDue(_ epoch: Int64) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(epoch))
        let f = RelativeDateTimeFormatter(); f.locale = Locale(identifier: "es")
        return f.localizedString(for: date, relativeTo: Date())
    }
}

struct StatTile: View {
    let title: String
    let value: Int
    let color: Color
    var body: some View {
        Panel(padding: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(value)")
                    .font(.system(size: 34, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(color)
                Text(title).font(.subheadline).foregroundStyle(Theme.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct ActionRow: View {
    let icon: String
    let title: String
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon).foregroundStyle(Theme.accent).frame(width: 24)
                Text(title).foregroundStyle(Theme.textPrimary)
                Spacer()
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(Theme.textTertiary)
            }
            .padding(.vertical, 14).padding(.horizontal, 16)
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: Theme.smallRadius, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
