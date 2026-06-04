//
//  RideTypeSelectionView.swift
//  RydrPlayground
//
//  Created by Khris Nunnally on 6/11/25.
//
import SwiftUI

struct RideTypeSelectionView: View {
    var userName: String = "Rydr User" // Replace with actual user data in future

    var body: some View {
        ZStack {
            LinearGradient(gradient: Gradient(colors: [Color.red, Color(red: 0.5, green: 0.0, blue: 0.13).opacity(0.7)]),
                           startPoint: .topLeading,
                           endPoint: .bottomTrailing)
                .edgesIgnoringSafeArea(.all)

            ScrollView {
                VStack(spacing: 20) {
                    Text("Choose Your Ride")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .foregroundStyle(LinearGradient(
                            gradient: Gradient(colors: [Color.white, Color.white]),
                            startPoint: .leading,
                            endPoint: .trailing
                        ))
                        .padding(.top)

                    // Rydr Go
                    NavigationLink(destination: BookingView(rideType: "Rydr Go", userName: userName)) {
                        RideOptionCard(title: "Rydr Go", subtitle: "Affordable everyday rides", icon: "car.fill")
                    }

                    // Rydr Eco
                    NavigationLink(destination: BookingView(rideType: "Rydr Eco", userName: userName)) {
                        RideOptionCard(title: "Rydr Eco", subtitle: "Electric vehicles like Tesla and Mach-E", icon: "leaf.fill")
                    }

                    // Rydr XL
                    NavigationLink(destination: BookingView(rideType: "Rydr XL", userName: userName)) {
                        RideOptionCard(title: "Rydr XL", subtitle: "More space for extra passengers", icon: "bus.fill")
                    }

                    // Rydr Prestine
                    NavigationLink(destination: BookingView(rideType: "Rydr Prestine", userName: userName)) {
                        RideOptionCard(title: "Rydr Prestine", subtitle: "Premium vehicles and top-rated drivers", icon: "sparkles")
                    }

                    // Rydr Executive
                    NavigationLink(destination: BookingView(rideType: "Rydr Executive", userName: userName)) {
                        RideOptionCard(title: "Rydr Executive", subtitle: "Professional black-car service", icon: "briefcase.fill")
                    }

                    // Cash Rydr Hub
                    NavigationLink(destination: CashRydrHubView()) {
                        RideOptionCard(title: "Cash Rydr Hub", subtitle: "Post or browse upcoming cash ride requests", icon: "rectangle.on.rectangle.angled")
                    }
                }
                .padding()
            }
        }
    }
}

struct RideOptionCard: View {
    var title: String
    var subtitle: String
    var icon: String

    var body: some View {
        HStack {
            Image(systemName: icon)
                .font(.system(size: 40))
                .foregroundColor(.red)
                .frame(width: 50)

            VStack(alignment: .leading) {
                Text(title)
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(.black)
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.gray)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .foregroundColor(.gray)
        }
        .padding()
        .background(Color.white.opacity(0.9))
        .cornerRadius(15)
        .shadow(radius: 3)
    }
}

#Preview {
    RideTypeSelectionView()
}
