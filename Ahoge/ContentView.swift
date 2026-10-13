// Modified for Ahoge from an Apache-2.0-licensed prior implementation.
// See THIRD_PARTY_NOTICES.md for attribution and license information.

//
//  ContentView.swift
//  Ahoge
//
//  Created by Giovan Christoffel Sihombing on 13/03/26.
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        AppChromeView()
            .background(AhogePalette.canvas)
            .tint(model.chromeTint)
            .preferredColorScheme(model.preferredColorScheme)
    }
}
