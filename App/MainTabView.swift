//
//  MainTabView.swift
//  RydrPlayground
//
//  Created by Khris Nunnally on 6/11/25.
//
import SwiftUI

struct MainTabView: View {
    @EnvironmentObject private var session: UserSessionManager
    @StateObject private var rideManager = RideManager()   // ✅ provide once here
    @State private var showRecoveredRide = false
    @State private var didRequestProfileLoad = false

    var body: some View {
        Group {
            if session.accountAccess == nil {
                ProgressView("Loading your account...")
            } else {
                tabs
            }
        }
        .task {
            if session.accountAccess == nil && !didRequestProfileLoad {
                didRequestProfileLoad = true
                session.loadUserProfile()
            }
            showRecoveredRide = rideManager.hasRecoveredActiveRide
        }
        .onChange(of: rideManager.hasRecoveredActiveRide, initial: false) { _, recovered in
            showRecoveredRide = recovered
        }
        .onChange(of: rideManager.state, initial: false) { _, newState in
            if newState == .idle || newState == .selecting || newState == .cancelled {
                showRecoveredRide = false
            }
        }
        .onChange(of: rideManager.currentRide?.id, initial: false) { _, rideId in
            if rideId == nil && rideManager.state != .completed {
                showRecoveredRide = false
            }
        }
        .fullScreenCover(isPresented: $showRecoveredRide, onDismiss: {
            rideManager.hasRecoveredActiveRide = false
        }) {
            RideInProgressView(rideManager: rideManager)
        }
        .accentColor(.red)
        .environmentObject(rideManager)             // ✅ inject to all tabs
    }

    private var tabs: some View {
        TabView(selection: $session.selectedTab) {
            if session.hasRiderAccess {
            // Ride
                NavigationStack {
                    RideTypeSelectionView()
                }
                .tag(MainAppTab.ride)
                .tabItem {
                    Image(systemName: "car.fill")
                    Text("Ride")
                }
            }

            // Cash Hub
            NavigationStack {
                CashRydrHubView()
            }
            .tag(MainAppTab.cashHub)
            .tabItem {
                Image(systemName: "rectangle.on.rectangle.angled")
                Text("Cash Hub")
            }

            // Profile
            NavigationStack {
                ProfileView()
            }
            .tag(MainAppTab.profile)
            .tabItem {
                Image(systemName: "person.crop.circle")
                Text("Profile")
            }

            if session.hasRiderAccess {
            // RydrBank
                NavigationStack {
                    RydrBankView()
                }
                .tag(MainAppTab.bank)
                .tabItem {
                    Image(systemName: "banknote.fill")
                    Text("RydrBank")
                }

                // Activity / History
                NavigationStack {
                    RideHistoryView()                 // ✅ real view
                        .navigationTitle("Activity")
                }
                .tag(MainAppTab.activity)
                .tabItem {
                    Image(systemName: "clock.arrow.circlepath")
                    Text("Activity")
                }
            }
        }
    }
}
