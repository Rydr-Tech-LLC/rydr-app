//
//  VehicleImageView.swift
//  RydrPlayground
//
//  Renders a vehicle or driver image that may come from either a bundled
//  asset name (legacy hardcoded test data) or a remote URL (the Vehicle
//  Library System's generic factory-style vehicle image, written by the
//  driver app to `publicDriverProfiles/{uid}.carImage` /
//  `.vehicleImageURL` — see RydrDriver's DriverDashboardVM). Riders never
//  see a photo of the driver's actual vehicle; this always renders either
//  a matched generic image or a graceful fallback, never a broken link.
//

import SwiftUI

/// Resolves `source` as a bundled asset name first, then as a remote URL,
/// and otherwise shows `fallback`.
struct VehicleOrDriverImage<Fallback: View>: View {
    let source: String?
    let contentMode: ContentMode
    @ViewBuilder var fallback: () -> Fallback

    var body: some View {
        if let source, !source.isEmpty, UIImage(named: source) != nil {
            Image(source)
                .resizable()
                .aspectRatio(contentMode: contentMode)
        } else if let source, !source.isEmpty, let url = URL(string: source) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: contentMode)
                case .failure:
                    fallback()
                case .empty:
                    ProgressView()
                @unknown default:
                    fallback()
                }
            }
        } else {
            fallback()
        }
    }
}
