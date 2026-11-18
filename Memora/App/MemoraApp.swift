//
//  MemoraApp.swift
//  Memora — a native, offline, Anki-compatible flashcards app for iPadOS.
//
//  Entry point. Creates the shared AppEnvironment and installs the root UI.
//

import SwiftUI

@main
struct MemoraApp: App {
    @StateObject private var env = AppEnvironment()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(env)
                .memoraStyle()
                .tint(Theme.accent)
        }
    }
}
