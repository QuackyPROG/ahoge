//
//  AhogeApp.swift
//  Ahoge
//
//  Created by Giovan Christoffel Sihombing on 13/03/26.
//

import SwiftUI

@main
struct AhogeApp: App {
    @StateObject private var model: AppModel

    init() {
        _model = StateObject(wrappedValue: AppModel(dependencies: .live))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
        }
    }
}
