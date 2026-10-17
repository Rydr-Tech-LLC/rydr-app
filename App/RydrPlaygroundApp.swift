//
//  RydrPlaygroundApp.swift
//  RydrPlayground
//
//  Created by Khris Nunnally on 6/11/25.
//

import SwiftUI
import Firebase

@main
struct RydrApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            #if DEBUG && targetEnvironment(simulator)
            if ProcessInfo.processInfo.arguments.contains("-RydrSMSUITest") {
                NavigationStack { LoginView().environmentObject(UserSessionManager()) }
            } else if ProcessInfo.processInfo.arguments.contains("-RiderCardSaveUITest") {
                RiderCardSaveUITestFixture()
            } else if ProcessInfo.processInfo.arguments.contains("-RiderOnboardingResumeUITest") {
                RiderOnboardingResumeUITestFixture()
            } else if ProcessInfo.processInfo.arguments.contains("-RydrIdentityOnboardingUITest") {
                IdentityOnboardingUITestFixture()
            } else { RydrWorkspaceGate { RiderWorkspaceContent() } }
            #else
            RydrWorkspaceGate { RiderWorkspaceContent() }
            #endif
        }
    }
}

private struct RiderWorkspaceContent: View {
    @StateObject private var session = UserSessionManager()
    @State private var showSplash = true
    @State private var prestineLightAppearance = false
    @AppStorage("appAppearance") private var appAppearance = RydrAppAppearance.system.rawValue

    var body: some View {
            Group {
                #if DEBUG && targetEnvironment(simulator)
                if ProcessInfo.processInfo.arguments.contains("-RydrSignupUITest") {
                    SignupAccountUIFixture()
                } else if ProcessInfo.processInfo.arguments.contains("-RydrPromotionsUITest") {
                    RiderPromotionPanel()
                } else if ProcessInfo.processInfo.arguments.contains("-PrestineBookingUITest") {
                    NavigationStack { RideTypeSelectionView(userName: "Test Rider") }
                        .environmentObject(session)
                        .environmentObject(RideManager())
                } else {
                    appContent
                }
                #else
                appContent
                #endif
            }
            .onPreferenceChange(PrestineLightAppearancePreference.self) { prestineLightAppearance = $0 }
            .preferredColorScheme(prestineLightAppearance && session.selectedTab == .ride ? .light : RydrAppAppearance(rawValue: appAppearance)?.colorScheme)
            .hideKeyboardOnTap()
    }

    private var appContent: some View {
        Group {
                if showSplash {
                    SplashVideoView { showSplash = false }
                } else {
                    if session.isLoggedIn {
                        RiderOnboardingGate {
                            MainTabView().environmentObject(session).onAppear { session.loadUserProfile() }
                        }.environmentObject(session)
                         .id("\(RydrWorkspace.identifier ?? "unresolved"):\(RydrWorkspace.auth.currentUser?.uid ?? "signed-out")")
                    } else {
                        WelcomeView().environmentObject(session)
                    }
                }
        }
    }
}


#if DEBUG && targetEnvironment(simulator)
private struct SignupAccountUIFixture: View {
    @State private var email = "rider@example.com"
    @State private var password = "Simulator123!"
    @State private var confirmation = "Simulator123!"
    @State private var advanced = false
    @State private var message = ""
    var body: some View {
        NavigationStack {
            if advanced {
                Text("Account step continued").accessibilityIdentifier("signupContinued")
            } else {
                EmailAndPasswordView(email: $email, password: $password, confirmPassword: $confirmation,
                                     submissionError: message) {
                    if ProcessInfo.processInfo.arguments.contains("-RydrSignupErrorUITest") {
                        message = "That email is already linked to an account. Log in with that account, or use a different email for this phone number."
                    } else { advanced = true }
                }
            }
        }
    }
}
#endif

#if DEBUG && targetEnvironment(simulator)
private struct IdentityOnboardingUITestFixture: View {
    @State private var complete = false
    @State private var accepted = true
    @State private var requested = false
    @State private var reads = 0
    var body: some View {
        if complete {
            Text("Onboarding complete").accessibilityIdentifier("identityOnboardingComplete")
        } else {
            TermsAndVerificationView(termsAccepted: $accepted, wantsVerification: $requested, onSubmit: { complete = true }, loadIdentityStatus: {
                reads += 1
                let args = ProcessInfo.processInfo.arguments
                let value = args.contains("-IdentityVerified") ? "verified" : args.contains("-IdentityReturnFailure") && reads == 1 ? "requires_input" : args.contains("-IdentityIncomplete") ? "requires_input" : "processing"
                return RiderIdentityStatus(identityVerified: value == "verified", verifiedRider: value == "verified", verifiedBadge: value == "verified", identityStatus: value)
            }, runIdentityVerification: {
                .flowFailed(error: URLError(.unsupportedURL))
            })
        }
    }
}
#endif


private struct RiderOnboardingGate<Content: View>: View {
    @EnvironmentObject private var session: UserSessionManager
    var fetchStatus: () async throws -> RiderOnboardingSnapshot = { try await RiderBackendIdentityService.onboardingStatus() }
    @ViewBuilder var content: () -> Content
    @State private var snapshot: RiderOnboardingSnapshot?
    @State private var failed = false
    var body: some View {
        Group {
            if let snapshot {
                if snapshot.completed { content() }
                else { SignupCoordinator(resumeSnapshot: snapshot, onCompleted: { Task { await reload() } }).id(snapshot.nextStep) }
            } else if failed {
                VStack(spacing: 20) {
                    Text("We couldn't confirm your onboarding progress. Please try again.").accessibilityIdentifier("riderOnboardingError")
                    Button("Retry") { Task { await reload() } }
                    Button("Sign out") { session.logout() }
                }.padding()
            } else { RydrLoadingView() }
        }.task { await reload() }
    }
    @MainActor private func reload() async {
        snapshot = nil; failed = false
        do {
            let result = try await fetchStatus()
            guard result.completed || result.nextStep == "phone" || result.nextStep.flatMap(SignupStep.resumeStep) != nil else { throw URLError(.cannotParseResponse) }
            snapshot = result
        } catch { failed = true }
    }
}

#if DEBUG && targetEnvironment(simulator)
private struct RiderOnboardingResumeUITestFixture: View {
    @StateObject private var session = UserSessionManager()
    var body: some View {
        RiderOnboardingGate(fetchStatus: {
            let args = ProcessInfo.processInfo.arguments
            if args.contains("-ResumeLoading") { try await Task.sleep(for: .seconds(6)) }
            if args.contains("-ResumeUnavailable") { throw URLError(.notConnectedToInternet) }
            let object: [String: Any] = ["completed": args.contains("-ResumeComplete"), "nextStep": "addressEntry", "cashHubOnly": false, "profile": ["firstName": "Test", "lastName": "Rider", "email": "fixture@example.com", "phoneNumber": "+16783220004", "address": ["street": "1 Main St", "city": "Atlanta", "state": "GA", "zip": "30303"]]]
            return try JSONDecoder().decode(RiderOnboardingSnapshot.self, from: JSONSerialization.data(withJSONObject: object))
        }) { Text("Rider dashboard").accessibilityIdentifier("riderDashboardFixture") }
        .environmentObject(session)
    }
}
#endif

#if DEBUG && targetEnvironment(simulator)
private struct RiderCardSaveUITestFixture: View {
    @State private var completed = false
    var body: some View {
        NavigationStack {
            if completed { Text("Card save completed once").accessibilityIdentifier("cardSaveCompleted") }
            else { PaymentScreenView(onComplete: { completed = true }) }
        }
    }
}
#endif
