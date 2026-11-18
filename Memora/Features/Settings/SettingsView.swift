//
//  SettingsView.swift
//  Memora
//
//  App-wide settings: appearance (text size), scheduling day rollover, data
//  management (backup / restore / export / integrity), and an About section
//  that states Memora's offline, no-account, no-tracking guarantees.
//

import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject var env: AppEnvironment
    @Environment(\.dismiss) private var dismiss

    @State private var rolloverHour = 4
    @State private var showRestore = false
    @State private var integrityResult: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Apariencia") {
                    VStack(alignment: .leading) {
                        Text("Tamaño del texto de las tarjetas: \(Int(env.textScale * 100))%")
                        Slider(value: $env.textScale, in: 0.7...1.8, step: 0.1)
                    }
                }
                Section("Programación") {
                    Stepper("Nuevo día a las \(rolloverHour):00", value: $rolloverHour, in: 0...23)
                        .onChange(of: rolloverHour) { _, newValue in updateRollover(newValue) }
                    Text("La hora a la que empieza un nuevo día de estudio (como en Anki, 4:00 por defecto).")
                        .font(.caption).foregroundStyle(Theme.textSecondary)
                }
                Section("Datos") {
                    Button { env.createBackup() } label: { Label("Crear copia de seguridad", systemImage: "externaldrive.badge.plus") }
                    Button { showRestore = true } label: { Label("Restaurar copia…", systemImage: "arrow.clockwise") }
                    Button { env.exportAPKG(deckIDs: nil, includeScheduling: true, suggestedName: "Memora-coleccion") } label: {
                        Label("Exportar toda la colección (.apkg)", systemImage: "square.and.arrow.up")
                    }
                    Button { runIntegrityCheck() } label: { Label("Comprobar integridad", systemImage: "checkmark.shield") }
                    if let integrityResult {
                        Text(integrityResult).font(.caption)
                            .foregroundStyle(integrityResult == "ok" ? Theme.good : Theme.again)
                    }
                }
                Section("Privacidad") {
                    Label("Funciona sin conexión", systemImage: "wifi.slash")
                    Label("Sin cuentas ni sincronización", systemImage: "person.crop.circle.badge.xmark")
                    Label("Sin anuncios ni rastreadores", systemImage: "hand.raised")
                    Text("Todos tus datos se guardan únicamente en este dispositivo.")
                        .font(.caption).foregroundStyle(Theme.textSecondary)
                }
                Section("Acerca de") {
                    LabeledContent("Versión", value: appVersion)
                    LabeledContent("Programadores", value: "FSRS-6 · SM-2")
                    Text("Memora es compatible con paquetes .apkg de Anki (formato heredado). FSRS-6 es el programador por defecto; SM-2 está disponible como alternativa.")
                        .font(.caption).foregroundStyle(Theme.textSecondary)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("Ajustes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Cerrar") { dismiss() } } }
            .onAppear { rolloverHour = (try? env.store.collectionSettings().rolloverHour) ?? 4 }
            .fileImporter(isPresented: $showRestore, allowedContentTypes: AnkiUTType.backupTypes, allowsMultipleSelection: false) { result in
                switch result {
                case .success(let urls): if let url = urls.first { env.restoreBackup(from: url) }
                case .failure(let error): env.presentError(error)
                }
            }
        }
    }

    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(v) (\(b))"
    }

    private func updateRollover(_ hour: Int) {
        do {
            var settings = try env.store.collectionSettings()
            settings.rolloverHour = hour
            try env.store.updateCollectionSettings(settings)
            env.refresh()
        } catch { env.presentError(error) }
    }

    private func runIntegrityCheck() {
        integrityResult = (try? env.store.integrityCheck()) ?? "error"
    }
}
