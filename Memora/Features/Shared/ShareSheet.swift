//
//  ShareSheet.swift
//  Memora
//
//  A thin wrapper around UIActivityViewController so exports and backups can be
//  saved to the Files app or shared. Everything stays on-device unless the user
//  chooses to share.
//

import SwiftUI
import UIKit

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
