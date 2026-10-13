//
//  AirPointerApp.swift
//  AirPointer
//
//  Created by Bruno on 7/21/25.
//

import SwiftUI

@main

struct AirPointerApp: App {
    @StateObject private var viewModel = ContentViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: viewModel)
        }
    }
}
