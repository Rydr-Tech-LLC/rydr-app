//
//  LocationManagerView.swift
//  RydrPlayground
//
//  Created by Khris Nunnally on 7/27/25.
//
import SwiftUI
import CoreLocation
import MapKit

struct LocationManagerView: View {
    @StateObject private var locationManager = LocationManager()

    // Atlanta fallback; centers on the device as soon as we get a fix
    @State private var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 33.7490, longitude: -84.3880),
        span: MKCoordinateSpan(latitudeDelta: 0.12, longitudeDelta: 0.12)
    )
    @State private var position: MapCameraPosition = .region(RydrMapDefaults.atlantaRegion)

    var body: some View {
        VStack(spacing: 16) {
            Map(position: $position) {
                UserAnnotation() // Shows current user location
            }
            .mapStyle(.standard(elevation: .realistic, pointsOfInterest: .excludingAll))
            .overlay(alignment: .topLeading) {
                Label("Rydr Map", systemImage: "location.north.line.fill")
                    .font(.caption2.weight(.black))
                    .foregroundStyle(Styles.rydrGradient)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(10)
            }
            .frame(height: 300)
            .clipShape(RoundedRectangle(cornerRadius: 12))
                // use a Publisher instead of onChange(of:) so we don’t need Equatable
                .onReceive(locationManager.$lastLocation.compactMap { $0 }) { loc in
                    region.center = loc.coordinate
                    position = .region(region)
                }
                .onAppear { locationManager.requestIfNeeded() }

            HStack(spacing: 12) {
                Button("Recenter") {
                    locationManager.recenter(&region)
                    position = .region(region)
                }
                Spacer()
                Text(labelFor(locationManager.authorization))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .navigationTitle("Your Location")
    }

    private func labelFor(_ status: CLAuthorizationStatus) -> String {
        switch status {
        case .notDetermined: return "Permission: Not Determined"
        case .restricted:    return "Permission: Restricted"
        case .denied:        return "Permission: Denied"
        case .authorizedWhenInUse: return "Permission: When In Use"
        case .authorizedAlways:    return "Permission: Always"
        @unknown default: return "Permission: Unknown"
        }
    }
}


