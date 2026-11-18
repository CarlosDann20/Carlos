//
//  StudyView.swift
//  Memora
//
//  The study screen: a centred card, a reveal button, and four large rating
//  buttons with interval previews. Optimised for iPad with keyboard shortcuts
//  (space to reveal, 1–4 to rate, z to undo).
//

import SwiftUI

struct StudyView: View {
    @EnvironmentObject var env: AppEnvironment
    @Environment(\.dismiss) private var dismiss
    @StateObject private var vm: StudyViewModel
    let deckID: Int64

    init(deckID: Int64, ignoreLimits: Bool = false) {
        self.deckID = deckID
        _vm = StateObject(wrappedValue: StudyViewModel(deckID: deckID, ignoreLimits: ignoreLimits))
    }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            if vm.finished {
                finishedView
            } else {
                VStack(spacing: 0) {
                    topBar
                    cardArea
                    controls
                }
            }
        }
        .onAppear {
            vm.configure(store: env.store)
            vm.onError = { env.presentError($0) }
            vm.start()
        }
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack(spacing: 16) {
            Button { dismiss() } label: { Image(systemName: "xmark").font(.headline) }
                .foregroundStyle(Theme.textSecondary)
            Spacer()
            HStack(spacing: 14) {
                CountPill(value: vm.newRemaining, color: Theme.newCard)
                CountPill(value: vm.learningCount, color: Theme.learnCard)
                CountPill(value: vm.reviewRemaining, color: Theme.reviewCard)
            }
            Spacer()
            Button { vm.undo() } label: { Image(systemName: "arrow.uturn.backward") }
                .foregroundStyle(vm.canUndo ? Theme.accent : Theme.textTertiary)
                .disabled(!vm.canUndo)
                .keyboardShortcut("z", modifiers: [])
        }
        .padding(.horizontal, 20).padding(.vertical, 14)
    }

    // MARK: - Card

    private var cardArea: some View {
        Group {
            if let rc = vm.rendered {
                let body = vm.showingAnswer ? rc.answerHTML : rc.questionHTML
                let doc = CardRenderer.document(body: body, css: rc.css, dark: true, textScale: env.textScale)
                CardWebView(html: doc, baseURL: env.mediaDirectory)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: Theme.cornerRadius).stroke(Theme.stroke, lineWidth: 1))
                    .padding(.horizontal, 20)
            } else {
                ProgressView().frame(maxHeight: .infinity)
            }
        }
        .frame(maxHeight: .infinity)
    }

    // MARK: - Controls

    @ViewBuilder private var controls: some View {
        VStack(spacing: 12) {
            if !vm.warnings.isEmpty {
                WarningBanner(messages: vm.warnings)
            }
            if vm.showingAnswer {
                HStack(spacing: 10) {
                    ratingButton(.again)
                    ratingButton(.hard)
                    ratingButton(.good)
                    ratingButton(.easy)
                }
            } else {
                Button { vm.reveal() } label: {
                    Text("Mostrar respuesta").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 10)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
                .keyboardShortcut(.space, modifiers: [])
            }
        }
        .padding(20)
    }

    private func ratingButton(_ rating: Rating) -> some View {
        Button { vm.answer(rating) } label: {
            VStack(spacing: 3) {
                Text(rating.localizedTitle).font(.subheadline.weight(.semibold))
                if vm.showIntervals {
                    Text(vm.intervalLabel(for: rating)).font(.caption2).opacity(0.9)
                }
            }
            .frame(maxWidth: .infinity).padding(.vertical, 12)
            .background(Theme.ratingColor(rating).opacity(0.18))
            .overlay(RoundedRectangle(cornerRadius: Theme.smallRadius).stroke(Theme.ratingColor(rating), lineWidth: 1))
            .foregroundStyle(Theme.ratingColor(rating))
            .clipShape(RoundedRectangle(cornerRadius: Theme.smallRadius, style: .continuous))
        }
        .keyboardShortcut(KeyEquivalent(Character("\(rating.rawValue)")), modifiers: [])
    }

    // MARK: - Finished

    private var finishedView: some View {
        VStack(spacing: 18) {
            Image(systemName: "checkmark.circle.fill").font(.system(size: 60)).foregroundStyle(Theme.good)
            Text("¡Sesión al día!").font(.title.bold()).foregroundStyle(Theme.textPrimary)
            Text(vm.waitingMessage ?? "Has repasado todas las tarjetas disponibles de este mazo por ahora.")
                .multilineTextAlignment(.center).foregroundStyle(Theme.textSecondary).padding(.horizontal, 40)
            Text("Respondidas en esta sesión: \(vm.answeredThisSession)")
                .font(.subheadline).foregroundStyle(Theme.textTertiary)
            HStack(spacing: 12) {
                if vm.canUndo {
                    Button { vm.undo() } label: { Label("Deshacer", systemImage: "arrow.uturn.backward") }
                        .buttonStyle(.bordered)
                }
                Button { dismiss() } label: { Text("Hecho").frame(minWidth: 100) }
                    .buttonStyle(.borderedProminent).tint(Theme.accent)
            }
        }
        .padding(40)
    }
}

struct WarningBanner: View {
    let messages: [String]
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.hard)
            VStack(alignment: .leading, spacing: 2) {
                ForEach(messages.prefix(3), id: \.self) { Text($0).font(.caption2) }
            }
            Spacer()
        }
        .foregroundStyle(Theme.textSecondary)
        .padding(10)
        .background(Theme.hard.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: Theme.smallRadius, style: .continuous))
    }
}
