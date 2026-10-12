// Modified for Ahoge from an Apache-2.0-licensed prior implementation.
// See THIRD_PARTY_NOTICES.md for attribution and license information.

import SwiftUI

struct AppChromeView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.scenePhase) private var scenePhase
    private let biometricLockEnabled = true

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
                    .fill(.ultraThinMaterial)
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
    let onBiometricFailure: () -> Void

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()

            VStack(spacing: 18) {
                Image(systemName: "faceid")
                    .font(.system(size: 38, weight: .semibold))
                    .foregroundStyle(.primary)

                Text("Ahoge Locked")
                    .font(.title3.weight(.semibold))

                Text(model.biometricErrorMessage ?? "Unlock with Face ID to continue.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)

                Button("Unlock") {
                    Task { await model.requestBiometricUnlock() }
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(28)
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
            LinearGradient(
                colors: [Color("LaunchGradientTop"), Color("LaunchGradientBottom")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 18) {
                Image(systemName: "book.pages")
                    .font(.system(size: 48))
                    .foregroundStyle(.white)
                ProgressView()
                    .tint(.white)
                Text("Loading Ahoge")
                    .font(.headline)
                    .foregroundStyle(.white.opacity(0.9))
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
    @State private var page = 0

    private let pageCount = 4

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                TabView(selection: $page) {
                    onboardingPage(
                        systemImage: "books.vertical.fill",
                        title: "Build your library",
                        message: "Keep the manga you care about together, organize it with categories, and jump back into what you were reading.",
                        footnote: "Your library and reading progress stay on this device."
                    )
                    .tag(0)

                    onboardingPage(
                        systemImage: "sparkle.magnifyingglass",
                        title: "Explore your sources",
                        message: "Search across enabled sources or browse each catalog directly. Source controls stay available without getting in the way of discovery.",
                        footnote: "Ahoge uses the sources you configure; it doesn't add a recommendation account or cloud service."
                    )
                    .tag(1)

                    onboardingPage(
                        systemImage: "book.pages.fill",
                        title: "Read your way",
                        message: "Resume from your last page and choose the reading mode, orientation, spread handling, and display filters that fit the chapter.",
                        footnote: "Reader progress is saved locally as you read."
                    )
                    .tag(2)

                    onboardingPage(
                        systemImage: "arrow.down.circle.fill",
                        title: "Keep chapters available",
                        message: "Download chapters for offline reading and manage transfers from Activity or the manga page.",
                        footnote: model.currentLanguageLabel.isEmpty ? nil : "Current language: \(model.currentLanguageLabel)"
                    )
                    .tag(3)
                }
                .tabViewStyle(.page(indexDisplayMode: .always))
                .animation(.easeInOut(duration: 0.2), value: page)

                HStack(spacing: 12) {
                    if page > 0 {
                        Button("Back") {
                            withAnimation { page -= 1 }
                        }
                        .buttonStyle(.bordered)
                    }

                    Button(page == pageCount - 1 ? "Start Reading" : "Continue") {
                        if page == pageCount - 1 {
                            model.markOnboardingCompleted()
                            dismiss()
                        } else {
                            withAnimation { page += 1 }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
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
        VStack(spacing: 24) {
            Spacer(minLength: 28)

            Image(systemName: systemImage)
                .font(.system(size: 58, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(model.chromeTint)
                .accessibilityHidden(true)

            VStack(spacing: 12) {
                Text(title)
                    .font(.title2.weight(.bold))
                    .multilineTextAlignment(.center)
                Text(message)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                if let footnote {
                    Text(footnote)
                        .font(.footnote)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 32)

            Spacer()
        }
        .accessibilityElement(children: .combine)
    }
}

private struct ReleaseNotesView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    releaseItem("A content-first Library built around covers and reading continuity.", systemImage: "books.vertical.fill")
                    releaseItem("Explore puts global search and source discovery before source administration.", systemImage: "sparkle.magnifyingglass")
                    releaseItem("Manga pages, Activity, downloads, and reader controls have a new native iOS presentation.", systemImage: "sparkles")
                }
                .padding(24)
            }
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
            Text(text)
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
