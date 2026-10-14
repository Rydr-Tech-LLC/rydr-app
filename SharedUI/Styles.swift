//
//  Styles.swift
//  RydrPlayground
//
//  Created by Khris Nunnally on 6/14/25.
//
import SwiftUI

struct GradientButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundColor(.white)
            .padding()
            .frame(maxWidth: .infinity)
            .background(
                LinearGradient(
                    gradient: Gradient(colors: [Color.red, Color(red: 0.5, green: 0.0, blue: 0.13).opacity(0.7)]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .cornerRadius(12)
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .shadow(radius: configuration.isPressed ? 1 : 4)
            .padding(.horizontal)
    }
}


// Shared ride accents travel through Booking and its driver-selection sheets.
enum PrestineTheme {
    static let gold = Color(red: 0.65, green: 0.43, blue: 0.13)
    static let gradient = LinearGradient(colors: [gold, Color(red: 0.40, green: 0.25, blue: 0.06)], startPoint: .topLeading, endPoint: .bottomTrailing)
    // Prestine deliberately keeps a light cream-and-white palette in every app appearance.
    static let cream = Color(red: 1, green: 0.97, blue: 0.91)
    static let ink = Color(red: 0.42, green: 0.27, blue: 0.07)
}
private struct RideGradientKey: EnvironmentKey { static let defaultValue = Styles.rydrGradient }
private struct RideAccentKey: EnvironmentKey { static let defaultValue = Color.red }
private struct RideSurfaceKey: EnvironmentKey { static let defaultValue = Color(.systemBackground) }
extension EnvironmentValues {
    var rydrRideGradient: LinearGradient { get { self[RideGradientKey.self] } set { self[RideGradientKey.self] = newValue } }
    var rydrRideAccent: Color { get { self[RideAccentKey.self] } set { self[RideAccentKey.self] = newValue } }
    var rydrRideSurface: Color { get { self[RideSurfaceKey.self] } set { self[RideSurfaceKey.self] = newValue } }
}
