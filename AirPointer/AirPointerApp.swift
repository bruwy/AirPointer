//
//  AirPointerApp.swift
//  AirPointer
//
//  Created by Bruno on 7/21/25.
//

import SwiftUI
import Combine

@main

struct AirPointerApp: App {
    @StateObject private var session = AirPointerSession()

    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: session.viewModel)
        }
    }
}

@MainActor
private final class AirPointerSession: ObservableObject {
    let viewModel: ContentViewModel
    private let cursorFeedback: CursorFeedbackWindowController
    private let laser: OverlayWindowController

    init() {
        let viewModel = ContentViewModel()
        self.viewModel = viewModel
        cursorFeedback = CursorFeedbackWindowController(viewModel: viewModel)
        laser = OverlayWindowController(viewModel: viewModel)
    }
}
