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

    var body: some View {
        Group {
            if session.accountAccess == nil {
                ProgressView("Loading your account...")
            } else {
                tabs
            }
        }
        .task {
            if session.accountAccess == nil {
                session.loadUserProfile()
            }
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

