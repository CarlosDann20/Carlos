//
//  NoteEditorView.swift
//  Memora
//
//  Add or edit a note: choose the note type and deck, fill the fields, manage
//  tags. Editing regenerates any newly-required cards without disturbing the
//  scheduling of existing ones.
//

import SwiftUI

struct NoteEditorView: View {
    enum Mode: Equatable { case add; case edit(noteID: Int64) }

    @EnvironmentObject var env: AppEnvironment
    @Environment(\.dismiss) private var dismiss
    let mode: Mode
    let defaultDeckID: Int64?

    @State private var notetypes: [Notetype] = []
    @State private var decks: [Deck] = []
    @State private var selectedNotetypeID: Int64?
    @State private var selectedDeckID: Int64 = 1
    @State private var fields: [String] = []
    @State private var fieldNames: [String] = []
    @State private var tagsText = ""
    @State private var noteID: Int64?

    private var isEditing: Bool { if case .edit = mode { return true } else { return false } }

    var body: some View {
        NavigationStack {
            Form {
                Section("Tipo y mazo") {
                    Picker("Tipo de nota", selection: $selectedNotetypeID) {
                        ForEach(notetypes) { Text($0.name).tag(Optional($0.id)) }
                    }
                    .disabled(isEditing)
                    .onChange(of: selectedNotetypeID) { _, _ in if !isEditing { rebuildFields() } }
                    Picker("Mazo", selection: $selectedDeckID) {
                        ForEach(decks) { Text($0.name).tag($0.id) }
                    }
                }
                Section("Campos") {
                    ForEach(fieldNames.indices, id: \.self) { i in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(fieldNames[i]).font(.caption).foregroundStyle(Theme.textSecondary)
                            TextEditor(text: Binding(
                                get: { i < fields.count ? fields[i] : "" },
                                set: { if i < fields.count { fields[i] = $0 } }))
                                .frame(minHeight: 60)
                                .scrollContentBackground(.hidden)
                                .padding(6)
                                .background(Theme.surfaceElevated)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
                Section("Etiquetas") {
                    TextField("separadas por espacios", text: $tagsText)
                        .textInputAutocapitalization(.never)
                }
                if isEditing {
                    Section {
                        Button(role: .destructive) { deleteNote() } label: {
                            Label("Eliminar nota", systemImage: "trash")
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle(isEditing ? "Editar nota" : "Nueva nota")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Guardar") { save() }.disabled(selectedNotetypeID == nil) }
            }
            .onAppear(perform: load)
        }
    }

    private func load() {
        notetypes = (try? env.store.allNotetypes()) ?? []
        decks = (try? env.store.allDecks().filter { !$0.isFiltered }) ?? []
        selectedDeckID = defaultDeckID ?? decks.first?.id ?? 1
        switch mode {
        case .add:
            selectedNotetypeID = notetypes.first?.id
            rebuildFields()
        case .edit(let id):
            noteID = id
            guard let note = try? env.store.note(id: id),
                  let nt = try? env.store.notetype(id: note.notetypeID) else { return }
            selectedNotetypeID = nt.id
            fieldNames = nt.fields.map { $0.name }
            fields = (0..<nt.fields.count).map { note.fields.indices.contains($0) ? note.fields[$0] : "" }
            tagsText = note.tags.joined(separator: " ")
            if let firstCard = try? env.store.cards(forNote: id).first { selectedDeckID = firstCard.deckID }
        }
    }

    private func rebuildFields() {
        guard let id = selectedNotetypeID, let nt = notetypes.first(where: { $0.id == id }) else { return }
        fieldNames = nt.fields.map { $0.name }
        fields = Array(repeating: "", count: nt.fields.count)
    }

    private func parsedTags() -> [String] {
        tagsText.split(whereSeparator: { $0 == " " }).map(String.init).filter { !$0.isEmpty }
    }

    private func save() {
        guard let ntID = selectedNotetypeID else { return }
        do {
            switch mode {
            case .add:
                try env.store.addNote(notetypeID: ntID, deckID: selectedDeckID, fields: fields, tags: parsedTags())
            case .edit(let id):
                if var note = try env.store.note(id: id) {
                    note.fields = fields
                    note.tags = parsedTags()
                    note.modified = Int64(Date().timeIntervalSince1970)
                    try env.store.saveNote(note)
                    try env.store.syncCards(for: note, deckID: selectedDeckID)
                    // Move existing cards to the chosen deck.
                    let cardIDs = try env.store.cards(forNote: id).map { $0.id }
                    try env.store.moveCards(cardIDs, toDeck: selectedDeckID)
                }
                _ = id
            }
            env.refresh()
            dismiss()
        } catch { env.presentError(error) }
    }

    private func deleteNote() {
        if let id = noteID { try? env.store.deleteNote(id: id); env.refresh(); dismiss() }
    }
}
