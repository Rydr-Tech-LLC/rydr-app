//
//  RideTypeSelectionView.swift
//  RydrPlayground
//
//  Created by Khris Nunnally on 6/11/25.
//
import SwiftUI

struct RideTypeSelectionView: View {
    var userName: String = "Rydr User" // Replace with actual user data in future
    private let rideTypes = ["Rydr Go", "Rydr Eco", "Rydr XL", "Rydr Prestine", "Rydr Executive"]

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

                    ForEach(rideTypes, id: \.self) { rideType in
                        let pricing = RideManager.pricingConfig(for: rideType)
                        NavigationLink(destination: BookingView(rideType: pricing.title, userName: userName)) {
                            RideOptionCard(
                                title: pricing.title,
                                subtitle: pricing.purpose,
                                detail: pricing.vehicleExpectations,
                                icon: icon(for: pricing.title)
                            )
                        }
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

    private func icon(for rideType: String) -> String {
        switch rideType {
        case "Rydr Eco": return "leaf.fill"
        case "Rydr XL": return "bus.fill"
        case "Rydr Prestine": return "sparkles"
        case "Rydr Executive": return "briefcase.fill"
        default: return "car.fill"
        }
    }
}

struct RideOptionCard: View {
    var title: String
    var subtitle: String
    var detail: String? = nil
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
                if let detail {
                    Text(detail)
                        .font(.caption2)
                        .foregroundColor(.gray)
                        .lineLimit(2)
                }
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
