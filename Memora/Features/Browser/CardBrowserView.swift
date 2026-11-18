//
//  CardBrowserView.swift
//  Memora
//
//  Browse all cards (optionally scoped to a deck): search by text, filter by
//  tag / favourites / suspended, sort, and act on cards (edit, delete, suspend,
//  favourite, move). Paged for responsiveness on large collections.
//

import SwiftUI

@MainActor
final class BrowserViewModel: ObservableObject {
    @Published var rows: [CardBrowseRow] = []
    @Published var totalCount = 0
    @Published var filter = CardBrowseFilter()
    @Published var tags: [String] = []
    private var store: MemoraStore!
    private var baseDeckIDs: [Int64]?

    func configure(store: MemoraStore, deckID: Int64?) {
        self.store = store
        if let deckID, let deck = try? store.deck(id: deckID) {
            baseDeckIDs = try? store.descendantDeckIDs(of: deck)
        } else {
            baseDeckIDs = nil
        }
        filter.deckIDs = baseDeckIDs
        tags = (try? store.allTags()) ?? []
    }

    func reload() {
        filter.offset = 0
        do {
            totalCount = try store.browseCount(filter)
            rows = try store.browse(filter)
        } catch { rows = [] }
    }

    func loadMore() {
        guard rows.count < totalCount else { return }
        filter.offset = rows.count
        if let more = try? store.browse(filter) { rows.append(contentsOf: more) }
    }

    func toggleFavorite(_ row: CardBrowseRow) {
        try? store.setFavorite(!row.favorite, cardIDs: [row.id]); reload()
    }
    func toggleSuspend(_ row: CardBrowseRow) {
        try? store.setSuspended(!row.suspended, cardIDs: [row.id]); reload()
    }
    func deleteNote(_ row: CardBrowseRow) {
        try? store.deleteNote(id: row.noteID); reload()
    }
}

struct CardBrowserView: View {
    @EnvironmentObject var env: AppEnvironment
    @Environment(\.dismiss) private var dismiss
    @StateObject private var vm = BrowserViewModel()
    let deckID: Int64?

    @State private var editingNoteID: Int64?
    @State private var showingAdd = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                filterBar
                if vm.rows.isEmpty {
                    ContentUnavailableView("Sin tarjetas", systemImage: "tray",
                                           description: Text("Ajusta la búsqueda o añade tarjetas."))
                        .frame(maxHeight: .infinity)
                } else {
                    List {
                        ForEach(vm.rows) { row in
                            CardBrowseRowView(row: row)
                                .contentShape(Rectangle())
                                .onTapGesture { editingNoteID = row.noteID }
                                .listRowBackground(Theme.surface)
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) { vm.deleteNote(row) } label: { Label("Eliminar", systemImage: "trash") }
                                    Button { vm.toggleSuspend(row) } label: {
                                        Label(row.suspended ? "Reanudar" : "Suspender", systemImage: row.suspended ? "play" : "pause")
                                    }.tint(.orange)
                                }
                                .swipeActions(edge: .leading) {
                                    Button { vm.toggleFavorite(row) } label: {
                                        Label("Favorita", systemImage: row.favorite ? "star.slash" : "star")
                                    }.tint(.yellow)
                                }
                                .onAppear { if row.id == vm.rows.last?.id { vm.loadMore() } }
                        }
                    }
                    .scrollContentBackground(.hidden)
                    .listStyle(.plain)
                }
            }
            .background(Theme.background)
            .navigationTitle("Explorar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cerrar") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) { Button { showingAdd = true } label: { Image(systemName: "plus") } }
                ToolbarItem(placement: .topBarTrailing) { sortMenu }
            }
            .searchable(text: $vm.filter.text, prompt: "Buscar en las tarjetas")
            .onChange(of: vm.filter.text) { _, _ in vm.reload() }
            .onAppear { vm.configure(store: env.store, deckID: deckID); vm.reload() }
            .onChange(of: env.dataVersion) { _, _ in vm.reload() }
            .sheet(item: Binding(get: { editingNoteID.map { IDBox(id: $0) } }, set: { editingNoteID = $0?.id })) { box in
                NoteEditorView(mode: .edit(noteID: box.id), defaultDeckID: deckID)
            }
            .sheet(isPresented: $showingAdd) {
                NoteEditorView(mode: .add, defaultDeckID: deckID)
            }
        }
    }

    private var filterBar: some View {
        HStack {
            Text("\(vm.totalCount) tarjetas").font(.caption).foregroundStyle(Theme.textSecondary)
            Spacer()
            Toggle("★", isOn: $vm.filter.favoritesOnly).toggleStyle(.button).tint(.yellow)
            Toggle("⏸", isOn: $vm.filter.suspendedOnly).toggleStyle(.button).tint(.orange)
        }
        .onChange(of: vm.filter.favoritesOnly) { _, _ in vm.reload() }
        .onChange(of: vm.filter.suspendedOnly) { _, _ in vm.reload() }
        .padding(.horizontal, 16).padding(.vertical, 8)
    }

    private var sortMenu: some View {
        Menu {
            Picker("Ordenar", selection: $vm.filter.sort) {
                ForEach(CardSortField.allCases, id: \.self) { Text($0.displayName).tag($0) }
            }
            Toggle("Ascendente", isOn: $vm.filter.ascending)
            if !vm.tags.isEmpty {
                Menu("Etiqueta") {
                    Button("Todas") { vm.filter.tag = nil; vm.reload() }
                    ForEach(vm.tags, id: \.self) { tag in
                        Button(tag) { vm.filter.tag = tag; vm.reload() }
                    }
                }
            }
        } label: { Image(systemName: "arrow.up.arrow.down") }
        .onChange(of: vm.filter.sort) { _, _ in vm.reload() }
        .onChange(of: vm.filter.ascending) { _, _ in vm.reload() }
    }
}

struct IDBox: Identifiable { let id: Int64 }

struct CardBrowseRowView: View {
    let row: CardBrowseRow
    var body: some View {
        HStack(spacing: 12) {
            Circle().fill(stateColor).frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.question.isEmpty ? "(vacío)" : row.question)
                    .foregroundStyle(Theme.textPrimary).lineLimit(1)
                if !row.answerPreview.isEmpty {
                    Text(row.answerPreview).font(.caption).foregroundStyle(Theme.textSecondary).lineLimit(1)
                }
            }
            Spacer()
            if row.favorite { Image(systemName: "star.fill").font(.caption2).foregroundStyle(.yellow) }
            if row.suspended { Image(systemName: "pause.circle").font(.caption2).foregroundStyle(.orange) }
        }
        .padding(.vertical, 4)
    }

    private var stateColor: Color {
        switch row.state {
        case .new: return Theme.newCard
        case .learning, .relearning: return Theme.learnCard
        case .review: return Theme.reviewCard
        }
    }
}
