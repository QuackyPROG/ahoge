// Modified for Ahoge from an Apache-2.0-licensed prior implementation.
// See THIRD_PARTY_NOTICES.md for attribution and license information.

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
