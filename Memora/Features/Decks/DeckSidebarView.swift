//
//  DeckSidebarView.swift
//  Memora
//

import SwiftUI

struct DeckSidebarView: View {
    @EnvironmentObject var env: AppEnvironment
    @StateObject private var model = DeckListViewModel()
    @Binding var selectedDeckID: Int64?
    @Binding var showImporter: Bool
    @Binding var showSettings: Bool
    @Binding var showStats: Bool
    @Binding var showBrowser: Bool

    @State private var showNewDeck = false
    @State private var newDeckName = ""

    var body: some View {
        List(selection: $selectedDeckID) {
            Section {
                ForEach(model.visibleNodes()) { node in
                    DeckRow(node: node) { toggleCollapse(node) }
                        .tag(node.deck.id)
                        .listRowBackground(Color.clear)
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) { delete(node.deck) } label: {
                                Label("Eliminar", systemImage: "trash")
                            }
                            Button { rename(node.deck) } label: {
                                Label("Renombrar", systemImage: "pencil")
                            }.tint(Theme.accent)
                        }
                }
            } header: {
                Text("Mazos").foregroundStyle(Theme.textSecondary)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .listStyle(.sidebar)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button { showNewDeck = true } label: { Image(systemName: "folder.badge.plus") }
                Menu {
                    Button { showImporter = true } label: { Label("Importar .apkg", systemImage: "square.and.arrow.down") }
                    Button { showBrowser = true } label: { Label("Explorar tarjetas", systemImage: "rectangle.stack") }
                    Button { showStats = true } label: { Label("Estadísticas", systemImage: "chart.bar") }
                    Button { showSettings = true } label: { Label("Ajustes", systemImage: "gearshape") }
                } label: { Image(systemName: "ellipsis.circle") }
            }
        }
        .onAppear { model.load(env.store) }
        .onChange(of: env.dataVersion) { _, _ in model.load(env.store) }
        .alert("Nuevo mazo", isPresented: $showNewDeck) {
            TextField("Nombre (usa :: para submazos)", text: $newDeckName)
            Button("Crear") { createDeck() }
            Button("Cancelar", role: .cancel) { newDeckName = "" }
        } message: {
            Text("Ej.: «Español::Verbos» crea un submazo.")
        }
        .alert("Renombrar mazo", isPresented: Binding(get: { renameTarget != nil }, set: { if !$0 { renameTarget = nil } })) {
            TextField("Nuevo nombre", text: $renameText)
            Button("Guardar") { performRename() }
            Button("Cancelar", role: .cancel) { renameTarget = nil }
        }
    }

    private func performRename() {
        guard let deck = renameTarget else { return }
        let leaf = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        renameTarget = nil
        guard !leaf.isEmpty else { return }
        let newFull: String
        if let parent = deck.parentName { newFull = parent + Deck.separator + leaf } else { newFull = leaf }
        do { try env.store.renameDeck(id: deck.id, to: newFull); env.refresh() }
        catch { env.presentError(error) }
    }

    private func createDeck() {
        let name = newDeckName.trimmingCharacters(in: .whitespacesAndNewlines)
        newDeckName = ""
        guard !name.isEmpty else { return }
        do { _ = try env.store.createDeck(name: name); env.refresh() }
        catch { env.presentError(error) }
    }

    private func toggleCollapse(_ node: DeckNode) {
        try? env.store.setDeckCollapsed(id: node.deck.id, collapsed: !node.deck.collapsed)
        env.refresh()
    }

    private func delete(_ deck: Deck) {
        do { try env.store.deleteDeck(id: deck.id); if selectedDeckID == deck.id { selectedDeckID = nil }; env.refresh() }
        catch { env.presentError(error) }
    }

    @State private var renameTarget: Deck?
    @State private var renameText = ""
    private func rename(_ deck: Deck) {
        // Present rename via a simple alert using a one-off state.
        renameTarget = deck
        renameText = deck.leafName
    }
}

struct DeckRow: View {
    let node: DeckNode
    var onToggle: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            if node.hasChildren {
                Button(action: onToggle) {
                    Image(systemName: node.deck.collapsed ? "chevron.right" : "chevron.down")
                        .font(.caption2)
                        .foregroundStyle(Theme.textTertiary)
                        .frame(width: 14)
                }.buttonStyle(.plain)
            } else {
                Spacer().frame(width: 14)
            }
            Image(systemName: node.deck.isFiltered ? "line.3.horizontal.decrease.circle" : "rectangle.stack.fill")
                .foregroundStyle(Theme.accent.opacity(0.9))
            Text(node.deck.leafName)
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
            Spacer()
            CountPill(value: node.counts.newCount, color: Theme.newCard)
            CountPill(value: node.counts.learningCount, color: Theme.learnCard)
            CountPill(value: node.counts.reviewCount, color: Theme.reviewCard)
        }
        .padding(.leading, CGFloat(node.depth) * 14)
        .padding(.vertical, 2)
    }
}

struct CountPill: View {
    let value: Int
    let color: Color
    var body: some View {
        Text("\(value)")
            .font(.caption2.weight(.semibold).monospacedDigit())
            .foregroundStyle(value == 0 ? Theme.textTertiary : color)
            .frame(minWidth: 22)
    }
}
