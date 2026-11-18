//
//  DeckOptionsView.swift
//  Memora
//
//  Per-deck study options (spec section 6): scheduler choice, daily limits,
//  (re)learning steps, FSRS retention / max interval / fuzz, SM-2 parameters,
//  ordering, sibling burying and leech handling.
//

import SwiftUI

struct DeckOptionsView: View {
    @EnvironmentObject var env: AppEnvironment
    @Environment(\.dismiss) private var dismiss
    let configID: Int64

    @State private var config = DeckConfig.makeDefault()
    @State private var learningStepsText = "1 10"
    @State private var relearningStepsText = "10"

    var body: some View {
        NavigationStack {
            Form {
                Section("Algoritmo") {
                    Picker("Programador", selection: $config.scheduler) {
                        ForEach(SchedulerKind.allCases, id: \.self) { Text($0.displayName).tag($0) }
                    }
                }
                Section("Límites diarios") {
                    Stepper("Nuevas por día: \(config.newPerDay)", value: $config.newPerDay, in: 0...9999, step: 5)
                    Stepper("Repasos por día: \(config.reviewsPerDay)", value: $config.reviewsPerDay, in: 0...99999, step: 10)
                }
                Section("Pasos (minutos)") {
                    LabeledContent("Aprendizaje") { TextField("1 10", text: $learningStepsText).multilineTextAlignment(.trailing) }
                    LabeledContent("Reaprendizaje") { TextField("10", text: $relearningStepsText).multilineTextAlignment(.trailing) }
                }
                if config.scheduler == .fsrs {
                    Section("FSRS") {
                        VStack(alignment: .leading) {
                            Text("Retención deseada: \(Int(config.desiredRetention * 100))%")
                            Slider(value: $config.desiredRetention, in: 0.7...0.97, step: 0.01)
                        }
                        Toggle("Variación aleatoria (fuzz)", isOn: $config.enableFuzz)
                        Stepper("Intervalo máx.: \(config.maximumIntervalDays) d", value: $config.maximumIntervalDays, in: 1...36500, step: 365)
                        Text("Parámetros FSRS-6 (21). Por defecto, los valores recomendados.")
                            .font(.caption).foregroundStyle(Theme.textSecondary)
                    }
                } else {
                    Section("SM-2") {
                        Stepper("Facilidad inicial: \(String(format: "%.2f", Double(config.startingEase)/1000))", value: $config.startingEase, in: 1300...3500, step: 50)
                        VStack(alignment: .leading) {
                            Text("Bonus fácil: \(String(format: "%.2f", config.easyBonus))")
                            Slider(value: $config.easyBonus, in: 1.0...2.0, step: 0.05)
                        }
                        VStack(alignment: .leading) {
                            Text("Modificador de intervalo: \(String(format: "%.2f", config.intervalModifier))")
                            Slider(value: $config.intervalModifier, in: 0.5...1.5, step: 0.05)
                        }
                        Stepper("Intervalo mínimo: \(config.minimumIntervalDays) d", value: $config.minimumIntervalDays, in: 1...30)
                    }
                }
                Section("Orden") {
                    Picker("Tarjetas nuevas", selection: $config.newCardOrder) {
                        ForEach(NewCardOrder.allCases, id: \.self) { Text($0.displayName).tag($0) }
                    }
                    Picker("Repasos", selection: $config.reviewCardOrder) {
                        ForEach(ReviewCardOrder.allCases, id: \.self) { Text($0.displayName).tag($0) }
                    }
                }
                Section("Hermanas y leeches") {
                    Toggle("Posponer nuevas hermanas", isOn: $config.buryNewSiblings)
                    Toggle("Posponer repasos hermanos", isOn: $config.buryReviewSiblings)
                    Stepper("Umbral de leech: \(config.leechThreshold)", value: $config.leechThreshold, in: 1...30)
                    Picker("Acción de leech", selection: $config.leechAction) {
                        Text("Suspender").tag(LeechAction.suspend)
                        Text("Solo etiquetar").tag(LeechAction.tagOnly)
                    }
                }
                Section("Interfaz") {
                    Toggle("Mostrar intervalos en los botones", isOn: $config.showIntervalsOnButtons)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("Opciones del mazo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Guardar") { save() } }
            }
            .onAppear(perform: load)
        }
    }

    private func load() {
        config = (try? env.store.deckConfig(id: configID)) ?? .makeDefault()
        learningStepsText = config.learningStepsMinutes.map { formatMinutes($0) }.joined(separator: " ")
        relearningStepsText = config.relearningStepsMinutes.map { formatMinutes($0) }.joined(separator: " ")
    }

    private func save() {
        config.learningStepsMinutes = parseSteps(learningStepsText, fallback: [1, 10])
        config.relearningStepsMinutes = parseSteps(relearningStepsText, fallback: [10])
        do { try env.store.saveDeckConfig(config); env.refresh(); dismiss() }
        catch { env.presentError(error) }
    }

    private func parseSteps(_ text: String, fallback: [Double]) -> [Double] {
        let values = text.split(whereSeparator: { $0 == " " || $0 == "," })
            .compactMap { Double($0.replacingOccurrences(of: ",", with: ".")) }
            .filter { $0 > 0 }
        return values.isEmpty ? fallback : values
    }

    private func formatMinutes(_ m: Double) -> String {
        m == m.rounded() ? String(Int(m)) : String(m)
    }
}
