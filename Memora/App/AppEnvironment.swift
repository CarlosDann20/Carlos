//
//  AppEnvironment.swift
//  Memora
//
//  App-wide dependency container and coordinator. Owns the MemoraStore, runs
//  heavy operations (import / export / backup / restore) on a background queue
//  while publishing progress, and signals the UI to refresh after mutations.
//

import Foundation
import SwiftUI
import Combine

struct BusyState: Identifiable {
    let id = UUID()
    var title: String
    var message: String
    var fraction: Double?   // nil = indeterminate
}

struct ShareItem: Identifiable { let id = UUID(); let url: URL }

@MainActor
final class AppEnvironment: ObservableObject {
    @Published private(set) var store: MemoraStore
    @Published var busy: BusyState?
    @Published var errorMessage: String?
    @Published var infoMessage: String?
    /// Set when a generated file (export / backup) is ready to be shared/saved.
    @Published var pendingShare: ShareItem?
    /// Bumped whenever data changes, so views can reload.
    @Published var dataVersion = 0

    // User preferences (persisted).
    @AppStorage("textScale") var textScale: Double = 1.0
    @AppStorage("rolloverHour") var rolloverHour: Int = 4

    private let workQueue = DispatchQueue(label: "app.memora.work", qos: .userInitiated)

    let databaseURL: URL
    let mediaDirectory: URL

    init() {
        let base = AppEnvironment.collectionDirectory()
        self.databaseURL = base.appendingPathComponent("collection.sqlite")
        self.mediaDirectory = base.appendingPathComponent("media")
        do {
            self.store = try MemoraStore(databaseURL: databaseURL, mediaDirectory: mediaDirectory)
        } catch {
            // As a last resort, use an in-memory store so the app still launches.
            self.store = (try? MemoraStore.inMemory()) ?? AppEnvironment.crashSafeStore()
            self.errorMessage = "No se pudo abrir la base de datos; se está usando una temporal."
        }
    }

    static func collectionDirectory() -> URL {
        let fm = FileManager.default
        let base = (try? fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
            ?? fm.temporaryDirectory
        return base.appendingPathComponent("Memora", isDirectory: true)
    }

    private static func crashSafeStore() -> MemoraStore {
        // Last-resort throwaway store so the app can still launch.
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("memora-fallback-\(UUID().uuidString)")
        return try! MemoraStore(databaseURL: tmp.appendingPathComponent("collection.sqlite"),
                                mediaDirectory: tmp.appendingPathComponent("media"))
    }

    func refresh() { dataVersion &+= 1 }

    // MARK: - Import

    func importAPKG(from pickedURL: URL) {
        let needsStop = pickedURL.startAccessingSecurityScopedResource()
        // Copy to a temp location we fully control before background work.
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("import-\(UUID().uuidString).apkg")
        do {
            try? FileManager.default.removeItem(at: temp)
            try FileManager.default.copyItem(at: pickedURL, to: temp)
        } catch {
            if needsStop { pickedURL.stopAccessingSecurityScopedResource() }
            self.errorMessage = "No se pudo leer el archivo seleccionado."
            return
        }
        if needsStop { pickedURL.stopAccessingSecurityScopedResource() }

        busy = BusyState(title: "Importando", message: "Preparando…", fraction: 0)
        let store = self.store
        workQueue.async { [weak self] in
            let importer = AnkiImporter(store: store)
            do {
                let summary = try importer.importPackage(at: temp) { progress in
                    DispatchQueue.main.async {
                        self?.busy = BusyState(title: "Importando", message: progress.message, fraction: progress.fraction)
                    }
                }
                try? FileManager.default.removeItem(at: temp)
                DispatchQueue.main.async {
                    self?.busy = nil
                    self?.refresh()
                    var msg = "Importado: \(summary.notesImported) notas, \(summary.cardsImported) tarjetas, \(summary.decks) mazos."
                    if summary.notesDuplicate > 0 { msg += " \(summary.notesDuplicate) duplicadas omitidas." }
                    if summary.mediaWritten > 0 { msg += " \(summary.mediaWritten) archivos multimedia." }
                    if !summary.warnings.isEmpty { msg += "\n\n" + summary.warnings.joined(separator: "\n") }
                    self?.infoMessage = msg
                }
            } catch {
                try? FileManager.default.removeItem(at: temp)
                DispatchQueue.main.async {
                    self?.busy = nil
                    self?.presentError(error)
                }
            }
        }
    }

    // MARK: - Export

    func exportAPKG(deckIDs: [Int64]?, includeScheduling: Bool, suggestedName: String) {
        let safeName = suggestedName.components(separatedBy: CharacterSet(charactersIn: "/\\:")).joined(separator: "-")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(safeName).apkg")
        try? FileManager.default.removeItem(at: url)
        busy = BusyState(title: "Exportando", message: "Generando paquete…", fraction: 0)
        let store = self.store
        workQueue.async { [weak self] in
            do {
                let exporter = AnkiExporter(store: store)
                try exporter.export(deckIDs: deckIDs, includeScheduling: includeScheduling, to: url) { f in
                    DispatchQueue.main.async { self?.busy?.fraction = f }
                }
                DispatchQueue.main.async {
                    self?.busy = nil
                    self?.pendingShare = ShareItem(url: url)
                }
            } catch {
                DispatchQueue.main.async { self?.busy = nil; self?.presentError(error) }
            }
        }
    }

    // MARK: - Backup / Restore

    func createBackup() {
        let formatter = DateFormatter(); formatter.dateFormat = "yyyy-MM-dd-HHmm"
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Memora-\(formatter.string(from: Date())).memora")
        try? FileManager.default.removeItem(at: url)
        busy = BusyState(title: "Copia de seguridad", message: "Creando…", fraction: 0)
        let store = self.store
        workQueue.async { [weak self] in
            do {
                try BackupManager.createBackup(store: store, to: url) { f in
                    DispatchQueue.main.async { self?.busy?.fraction = f }
                }
                DispatchQueue.main.async { self?.busy = nil; self?.pendingShare = ShareItem(url: url) }
            } catch {
                DispatchQueue.main.async { self?.busy = nil; self?.presentError(error) }
            }
        }
    }

    func restoreBackup(from pickedURL: URL) {
        let needsStop = pickedURL.startAccessingSecurityScopedResource()
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("restore-\(UUID().uuidString).memora")
        do {
            try? FileManager.default.removeItem(at: temp)
            try FileManager.default.copyItem(at: pickedURL, to: temp)
        } catch {
            if needsStop { pickedURL.stopAccessingSecurityScopedResource() }
            self.errorMessage = "No se pudo leer la copia."
            return
        }
        if needsStop { pickedURL.stopAccessingSecurityScopedResource() }

        busy = BusyState(title: "Restaurando", message: "Validando copia…", fraction: 0)
        let dbURL = databaseURL
        let mediaDir = mediaDirectory
        workQueue.async { [weak self] in
            do {
                let manifest = try BackupManager.restore(from: temp, databaseURL: dbURL, mediaDirectory: mediaDir) { f in
                    DispatchQueue.main.async { self?.busy?.fraction = f }
                }
                try? FileManager.default.removeItem(at: temp)
                DispatchQueue.main.async {
                    self?.reopenStore()
                    self?.busy = nil
                    self?.refresh()
                    self?.infoMessage = "Copia restaurada: \(manifest.noteCount) notas, \(manifest.cardCount) tarjetas."
                }
            } catch {
                try? FileManager.default.removeItem(at: temp)
                DispatchQueue.main.async { self?.busy = nil; self?.presentError(error) }
            }
        }
    }

    func reopenStore() {
        if let fresh = try? MemoraStore(databaseURL: databaseURL, mediaDirectory: mediaDirectory) {
            self.store = fresh
        }
    }

    // MARK: - Error presentation

    func presentError(_ error: Error) {
        if let m = error as? MemoraError {
            var text = m.message
            if let r = m.recovery { text += "\n\n" + r }
            errorMessage = text
        } else {
            errorMessage = error.localizedDescription
        }
    }
}
