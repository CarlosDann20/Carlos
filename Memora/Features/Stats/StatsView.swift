//
//  StatsView.swift
//  Memora
//
//  Local statistics: today's activity, review history, upcoming due forecast,
//  card-state distribution and an activity calendar. All computed on-device
//  from the review log.
//

import SwiftUI
import Charts

@MainActor
final class StatsViewModel: ObservableObject {
    @Published var today = TodayStats()
    @Published var history: [DayBucket] = []
    @Published var forecast: [DueForecastBucket] = []
    @Published var distribution = StateDistribution()
    @Published var totalReviews = 0
    @Published var totalTimeHours = 0.0

    func load(store: MemoraStore, deckID: Int64?) {
        var deckIDs: [Int64]? = nil
        if let deckID, let deck = try? store.deck(id: deckID) {
            deckIDs = try? store.descendantDeckIDs(of: deck)
        }
        today = (try? store.todayStats()) ?? TodayStats()
        history = (try? store.dailyBuckets(daysBack: 30)) ?? []
        forecast = (try? store.dueForecast(days: 30)) ?? []
        distribution = (try? store.stateDistribution(deckIDs: deckIDs)) ?? StateDistribution()
        totalReviews = (try? store.totalReviews()) ?? 0
        totalTimeHours = Double((try? store.totalStudyTimeMS()) ?? 0) / 3_600_000.0
    }
}

struct StatsView: View {
    @EnvironmentObject var env: AppEnvironment
    @Environment(\.dismiss) private var dismiss
    @StateObject private var vm = StatsViewModel()
    let deckID: Int64?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    todaySection
                    historyChart
                    forecastChart
                    distributionSection
                    calendarSection
                    totalsSection
                }
                .padding(18)
            }
            .background(Theme.background)
            .navigationTitle("Estadísticas")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Cerrar") { dismiss() } } }
            .onAppear { vm.load(store: env.store, deckID: deckID) }
        }
    }

    private var todaySection: some View {
        Panel {
            VStack(alignment: .leading, spacing: 12) {
                Text("Hoy").font(.headline).foregroundStyle(Theme.textPrimary)
                HStack(spacing: 12) {
                    MiniStat(value: "\(vm.today.answered)", label: "Respuestas", color: Theme.accent)
                    MiniStat(value: "\(Int(vm.today.retentionPercent))%", label: "Aciertos", color: Theme.good)
                    MiniStat(value: String(format: "%.0f min", vm.today.timeMinutes), label: "Tiempo", color: Theme.easy)
                }
                HStack(spacing: 12) {
                    MiniStat(value: "\(vm.today.newIntroduced)", label: "Nuevas", color: Theme.newCard)
                    MiniStat(value: "\(vm.today.reviewsDone)", label: "Repasos", color: Theme.reviewCard)
                    MiniStat(value: "\(vm.today.learningDone)", label: "Aprendizaje", color: Theme.learnCard)
                }
            }
        }
    }

    private var historyChart: some View {
        Panel {
            VStack(alignment: .leading, spacing: 8) {
                Text("Repasos (últimos 30 días)").font(.headline).foregroundStyle(Theme.textPrimary)
                Chart(vm.history) { b in
                    BarMark(x: .value("Día", Date(timeIntervalSince1970: TimeInterval(b.startEpoch))),
                            y: .value("Repasos", b.reviews))
                    .foregroundStyle(Theme.accent)
                }
                .frame(height: 160)
            }
        }
    }

    private var forecastChart: some View {
        Panel {
            VStack(alignment: .leading, spacing: 8) {
                Text("Próximos vencimientos (30 días)").font(.headline).foregroundStyle(Theme.textPrimary)
                Chart(vm.forecast) { b in
                    BarMark(x: .value("Día", b.dayOffset), y: .value("Tarjetas", b.count))
                        .foregroundStyle(Theme.reviewCard)
                }
                .frame(height: 140)
            }
        }
    }

    private var distributionSection: some View {
        Panel {
            VStack(alignment: .leading, spacing: 8) {
                Text("Distribución de tarjetas").font(.headline).foregroundStyle(Theme.textPrimary)
                let items: [(String, Int, Color)] = [
                    ("Nuevas", vm.distribution.new, Theme.newCard),
                    ("Aprendiendo", vm.distribution.learning + vm.distribution.relearning, Theme.learnCard),
                    ("Jóvenes", vm.distribution.youngReview, Theme.good.opacity(0.7)),
                    ("Maduras", vm.distribution.matureReview, Theme.good),
                    ("Suspendidas", vm.distribution.suspended, Theme.textTertiary)
                ]
                Chart(items, id: \.0) { item in
                    BarMark(x: .value("Cantidad", item.1), y: .value("Tipo", item.0))
                        .foregroundStyle(item.2)
                }
                .frame(height: 180)
                Text("Total: \(vm.distribution.total) tarjetas").font(.caption).foregroundStyle(Theme.textSecondary)
            }
        }
    }

    private var calendarSection: some View {
        Panel {
            VStack(alignment: .leading, spacing: 8) {
                Text("Actividad").font(.headline).foregroundStyle(Theme.textPrimary)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 3) {
                        ForEach(vm.history) { b in
                            RoundedRectangle(cornerRadius: 3)
                                .fill(heat(b.reviews))
                                .frame(width: 14, height: 14)
                        }
                    }
                }
            }
        }
    }

    private var totalsSection: some View {
        Panel {
            HStack {
                MiniStat(value: "\(vm.totalReviews)", label: "Repasos totales", color: Theme.accent)
                MiniStat(value: String(format: "%.1f h", vm.totalTimeHours), label: "Tiempo total", color: Theme.easy)
            }
        }
    }

    private func heat(_ reviews: Int) -> Color {
        switch reviews {
        case 0: return Theme.surfaceElevated
        case 1..<10: return Theme.good.opacity(0.3)
        case 10..<30: return Theme.good.opacity(0.6)
        default: return Theme.good
        }
    }
}

struct MiniStat: View {
    let value: String
    let label: String
    let color: Color
    var body: some View {
        VStack(spacing: 3) {
            Text(value).font(.title3.weight(.bold).monospacedDigit()).foregroundStyle(color)
            Text(label).font(.caption2).foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }
}
