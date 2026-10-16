// Modified for Ahoge from an Apache-2.0-licensed prior implementation.
// See THIRD_PARTY_NOTICES.md for attribution and license information.

import SwiftUI

struct AppChromeView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.scenePhase) private var scenePhase
    private let biometricLockEnabled = true

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var showBiometricRetryAlert = false

    private var isPrivacyOverlayActive: Bool {
        model.state.securityPreferences.blurAppSwitcher && scenePhase != .active
    }

    private var isBiometricLockActive: Bool {
        biometricLockEnabled
            && model.state.securityPreferences.requireBiometricUnlock
            && !model.isAppUnlocked
            && scenePhase == .active
    }

    var body: some View {
        ZStack {
            Group {
                switch model.bootState {
                case .launching:
                    LaunchView()
                case .failed(let message):
                    CrashView(message: message)
                case .ready:
                    RootTabView()
                        .sheet(isPresented: onboardingBinding) {
                            OnboardingView()
                        }
                        .sheet(isPresented: $model.releaseNotesPresented) {
                            ReleaseNotesView()
                        }
                }
            }
            .accessibilityHidden(isPrivacyOverlayActive || isBiometricLockActive)

            if isPrivacyOverlayActive {
                Rectangle()
                    .fill(reduceTransparency ? AnyShapeStyle(AhogePalette.canvas) : AnyShapeStyle(.ultraThinMaterial))
                    .ignoresSafeArea()
                VStack(spacing: 12) {
                    Image(systemName: "lock.fill")
                        .font(.title2)
                    Text("Ahoge Hidden")
                        .font(.headline)
                }
                .foregroundStyle(.primary)
            }

            if isBiometricLockActive {
                BiometricLockView(onBiometricFailure: {
                    showBiometricRetryAlert = true
                })
                .transition(.opacity)
            }
        }
        .alert("Face ID Failed", isPresented: $showBiometricRetryAlert) {
            Button("Retry") {
                Task { await model.requestBiometricUnlock() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(model.biometricErrorMessage ?? "Authentication failed. Please try again.")
        }
        .onAppear {
            if biometricLockEnabled && model.state.securityPreferences.requireBiometricUnlock {
                model.lockAppIfNeeded()
                Task { await model.unlockAppIfNeeded() }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                if biometricLockEnabled {
                    Task { await model.unlockAppIfNeeded() }
                }
            case .inactive:
                break
            case .background:
                if biometricLockEnabled {
                    model.lockAppIfNeeded()
                }
            @unknown default:
                break
            }
        }
    }

    private var onboardingBinding: Binding<Bool> {
        Binding(
            get: { !model.state.onboardingCompleted },
            set: { newValue in
                if !newValue {
                    model.markOnboardingCompleted()
                }
            }
        )
    }
}

private struct BiometricLockView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    let onBiometricFailure: () -> Void

    var body: some View {
        ZStack {
            Rectangle()
                .fill(reduceTransparency ? AnyShapeStyle(AhogePalette.canvas) : AnyShapeStyle(.ultraThinMaterial))
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 24) {
                    Image(systemName: "faceid")
                        .font(.largeTitle.weight(.semibold))
                        .foregroundStyle(.primary)

                    Text("Ahoge Locked")
                        .font(.system(.title, design: .rounded, weight: .bold))

                    Text(model.biometricErrorMessage ?? "Unlock with Face ID to continue.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 28)

                    Button("Unlock") {
                        Task { await model.requestBiometricUnlock() }
                    }
                    .buttonStyle(.borderedProminent)
                .controlSize(.large)
                }
                .frame(maxWidth: 560)
                .padding(28)
                .frame(maxWidth: .infinity)
            }
        }
        .onChange(of: model.biometricErrorMessage) { _, newValue in
            guard let message = newValue, !message.isEmpty else { return }
            onBiometricFailure()
        }
    }
}

private struct LaunchView: View {
    var body: some View {
        ZStack {
            AhogePalette.canvas.ignoresSafeArea()

            VStack(spacing: 18) {
                Image(systemName: "book.pages")
                    .font(.largeTitle)
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
                ProgressView()
                    .tint(.accentColor)
                Text("Loading Ahoge")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct CrashView: View {
    let message: String

    var body: some View {
        ContentUnavailableView(
            "Unable to Launch",
            systemImage: "exclamationmark.triangle",
            description: Text(message)
        )
    }
}

private struct OnboardingView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var page = 0

    private let pageCount = 2

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 28) {
                        Text("Step \(page + 1) of \(pageCount)")
                            .font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                        if page == 0 {
                            onboardingPage(
                                systemImage: "books.vertical",
                                title: "Build your library",
                                message: "Choose sources in Browse, or import local files, then add titles to Library and organize them with categories.",
                                footnote: "Your library and reading progress stay on this device."
                            )
                            onboardingTip("Choose your sources", message: "Search enabled sources or add a source repository. Local imports work with files you choose.", systemImage: "safari")
                            NavigationLink("Choose Sources") { SourcesView() }
                            NavigationLink("Import Local Files") { LocalImportsView() }
                            NavigationLink("Restore an Ahoge Backup") { RestoreBackupView() }
                        } else {
                            onboardingPage(
                                systemImage: "book.pages",
                                title: "Read and keep your data",
                                message: "Continue from your last page and choose the reading mode, orientation, and display settings that feel right for each chapter.",
                                footnote: model.currentLanguageLabel.isEmpty ? nil : "Current language: \(model.currentLanguageLabel)"
                            )
                            onboardingTip("Take chapters with you", message: "Download chapters from a title’s chapter list. Manage the Download Queue from More or by tapping Updates again.", systemImage: "arrow.down.circle")
                            NavigationLink("Reader Preferences") { ReaderSettingsView() }
                            NavigationLink("Backup & Storage") { DataStorageView() }
                        }
                    }
                    .frame(maxWidth: 560, alignment: .leading)
                    .padding(24)
                    .frame(maxWidth: .infinity)
                }
                Divider()

                HStack(spacing: 12) {
                    if page > 0 {
                        Button("Back") {
                            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { page -= 1 }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                    }

                    Button(page == pageCount - 1 ? "Start Reading" : "Continue") {
                        if page == pageCount - 1 {
                            model.markOnboardingCompleted()
                            dismiss()
                        } else {
                            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { page += 1 }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
            }
            .navigationTitle("Welcome to Ahoge")
            .navigationBarTitleDisplayMode(.inline)
        }
        .interactiveDismissDisabled()
    }

    private func onboardingPage(
        systemImage: String,
        title: String,
        message: String,
        footnote: String?
    ) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            Image(systemName: systemImage)
                .font(.largeTitle).foregroundStyle(model.chromeTint).accessibilityHidden(true)
            Text(title).font(.title.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true).accessibilityAddTraits(.isHeader)
            Text(message).font(.body).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let footnote {
                Text(footnote).font(.footnote).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func onboardingTip(_ title: String, message: String, systemImage: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Divider()
            Label(title, systemImage: systemImage).font(.headline)
            Text(message).font(.body).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

}

private struct ReleaseNotesView: View {
    @Environment(\.dismiss) private var dismiss

    private var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Ahoge")
                            .font(.system(.title, design: .rounded, weight: .bold))
                        if !currentVersion.isEmpty {
                            Text("Ahoge \(currentVersion)")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }

                    releaseItem("Library now offers categories, compact grid/list views, chapter filters and selection actions.", systemImage: "books.vertical.fill")
                    releaseItem("Browse sources and search enabled sources from Browse.", systemImage: "sparkle.magnifyingglass")
                    releaseItem("Updates and History have separate tabs; tap Updates again to open the Download Queue.", systemImage: "clock.arrow.circlepath")
                    releaseItem("Manage chapter read state, bookmarks and downloads from a title’s chapter list.", systemImage: "sparkles")
                    releaseItem("More includes local tracking records, statistics, backup, storage and preferences.", systemImage: "iphone")
                }
                .frame(maxWidth: 760, alignment: .leading)
                .padding(24)
                .frame(maxWidth: .infinity)
            }
            .background(AhogePalette.canvas)
            .navigationTitle("What's New")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func releaseItem(_ text: String, systemImage: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: systemImage)
                .font(.title3)
                .frame(width: 28)
                .accessibilityHidden(true)
            Text(text)
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
