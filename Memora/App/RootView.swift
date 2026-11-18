//
//  RootView.swift
//  Memora
//
//  The top-level iPad layout: a sidebar of decks and a detail panel. Global
//  overlays (busy HUD, alerts) and the import/backup file pickers live here.
//

import SwiftUI
import UniformTypeIdentifiers

struct RootView: View {
    @EnvironmentObject var env: AppEnvironment
    @State private var selectedDeckID: Int64?
    @State private var showImporter = false
    @State private var showSettings = false
    @State private var showStats = false
    @State private var showBrowser = false

    var body: some View {
        NavigationSplitView {
            DeckSidebarView(selectedDeckID: $selectedDeckID,
                            showImporter: $showImporter,
                            showSettings: $showSettings,
                            showStats: $showStats,
                            showBrowser: $showBrowser)
            .navigationTitle("Memora")
            .background(Theme.background)
        } detail: {
            if let id = selectedDeckID {
                DeckDetailView(deckID: id)
                    .id(id)
                    .background(Theme.background)
            } else {
                WelcomeView(showImporter: $showImporter)
                    .background(Theme.background)
            }
        }
        .tint(Theme.accent)
        .fileImporter(isPresented: $showImporter,
                      allowedContentTypes: AnkiUTType.importTypes,
                      allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls): if let url = urls.first { env.importAPKG(from: url) }
            case .failure(let error): env.presentError(error)
            }
        }
        .sheet(isPresented: $showSettings) { SettingsView() }
        .sheet(isPresented: $showStats) { StatsView(deckID: nil) }
        .sheet(isPresented: $showBrowser) { CardBrowserView(deckID: nil) }
        .sheet(item: $env.pendingShare) { item in ShareSheet(items: [item.url]) }
        .overlay { if let busy = env.busy { BusyOverlay(state: busy) } }
        .alert("Aviso", isPresented: Binding(get: { env.errorMessage != nil }, set: { if !$0 { env.errorMessage = nil } })) {
            Button("Entendido", role: .cancel) { env.errorMessage = nil }
        } message: { Text(env.errorMessage ?? "") }
        .alert("Listo", isPresented: Binding(get: { env.infoMessage != nil }, set: { if !$0 { env.infoMessage = nil } })) {
            Button("Aceptar", role: .cancel) { env.infoMessage = nil }
        } message: { Text(env.infoMessage ?? "") }
    }
}

enum AnkiUTType {
    static let apkg = UTType(filenameExtension: "apkg") ?? .data
    static let colpkg = UTType(filenameExtension: "colpkg") ?? .data
    static let memora = UTType(filenameExtension: "memora") ?? .data
    static var importTypes: [UTType] { [apkg, colpkg, .zip, .data] }
    static var backupTypes: [UTType] { [memora, .zip, .data] }
}

struct WelcomeView: View {
    @EnvironmentObject var env: AppEnvironment
    @Binding var showImporter: Bool
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "rectangle.on.rectangle.angled")
                .font(.system(size: 64, weight: .light))
                .foregroundStyle(Theme.accent)
            Text("Bienvenido a Memora")
                .font(.largeTitle.bold())
                .foregroundStyle(Theme.textPrimary)
            Text("Selecciona un mazo en la barra lateral para empezar a estudiar,\no importa un paquete .apkg de Anki.")
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.textSecondary)
            Button {
                showImporter = true
            } label: {
                Label("Importar paquete .apkg", systemImage: "square.and.arrow.down")
                    .padding(.horizontal, 8)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct BusyOverlay: View {
    let state: BusyState
    var body: some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()
            VStack(spacing: 16) {
                if let f = state.fraction {
                    ProgressView(value: f) { Text(state.title).font(.headline) }
                        .progressViewStyle(.linear)
                        .frame(width: 260)
                } else {
                    ProgressView().controlSize(.large)
                    Text(state.title).font(.headline)
                }
                Text(state.message)
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(28)
            .background(Theme.surfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
            .frame(maxWidth: 320)
        }
    }
}
