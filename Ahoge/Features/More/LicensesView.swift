import SwiftUI

struct LicensesView: View {
    var body: some View {
        List {
            Section("Ahoge") { Text("Apache License 2.0. https://github.com/QuackyPROG/ahoge") }.themedRows()
            Section("SwiftSoup") { Text("MIT License. https://github.com/scinfu/SwiftSoup") }.themedRows()
            Section("Sources") {
                Text("Source logic is ported from keiyoushi/extensions-source, Apache License 2.0. Behavior is modeled on Mihon, Apache License 2.0.")
            }
            .themedRows()
        }
        .navigationTitle("Licenses")
        .themedScreen()
    }
}
