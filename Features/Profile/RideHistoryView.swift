//
//  RideHistoryView.swift
//  RydrPlayground
//
//  Created by Khris Nunnally on 8/24/25.
//


import SwiftUI
import MapKit

struct RideHistoryView: View {
    @EnvironmentObject var rideManager: RideManager

    enum Window: String, CaseIterable, Identifiable { case d30 = "30D", d90 = "90D", y1 = "1Y"; var id: String { rawValue } }
    @State private var window: Window = .d30

    private var cutoffDate: Date {
        let days: Int = (window == .d30 ? 30 : window == .d90 ? 90 : 365)
        return Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date.distantPast
    }

    private var filtered: [Receipt] {
        rideManager.history.filter { $0.date >= cutoffDate }
    }

    private let cols = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                // Filter
                Picker("Range", selection: $window) {
                    ForEach(Window.allCases) { w in
                        Text(w.rawValue).tag(w)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)

                if filtered.isEmpty {
                    ContentUnavailableView("No rides in this range", systemImage: "clock.arrow.circlepath",
                                           description: Text("Choose a wider range to see more."))
                        .padding(.top, 40)
                } else {
                    LazyVGrid(columns: cols, spacing: 12) {
                        ForEach(filtered) { r in
                            NavigationLink {
                                RideReceiptDetailView(receipt: r)
                            } label: {
                                RideTile(receipt: r)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 16)
                }
            }
            .navigationTitle("Ride History")
        }
    }
}

// MARK: - Tile
private struct RideTile: View {
    let receipt: Receipt

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            RydrReceiptRouteMap(pickup: pseudoCoord(from: receipt.pickup),
                                dropoff: pseudoCoord(from: receipt.dropoff))
                .frame(height: 120)
                .clipShape(RoundedRectangle(cornerRadius: 12))

            // Title/subtitle
            VStack(alignment: .leading, spacing: 4) {
                Text(short(receipt.pickup) + " → " + short(receipt.dropoff))
                    .font(.subheadline).bold()
                    .lineLimit(1)
                HStack {
                    Text(receipt.date.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Text("$" + String(format: "%.2f", receipt.fare))
                        .font(.subheadline).bold()
                }
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 14).fill(.thinMaterial))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.black.opacity(0.06), lineWidth: 1))
    }

    private func short(_ s: String) -> String {
        // first chunk before comma, else whole
        s.split(separator: ",").first.map(String.init) ?? s
    }
}

// MARK: - Receipt Detail
struct RideReceiptDetailView: View {
    let receipt: Receipt

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                RydrReceiptRouteMap(pickup: pseudoCoord(from: receipt.pickup),
                                    dropoff: pseudoCoord(from: receipt.dropoff))
                    .frame(height: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.black.opacity(0.06), lineWidth: 1))

                // Summary card
                VStack(alignment: .leading, spacing: 10) {
                    receiptRow("Driver", receipt.driverName)
                    receiptRow("When", receipt.date.formatted(date: .abbreviated, time: .shortened))
                    receiptRow("Route", receipt.pickup + " → " + receipt.dropoff, lineLimit: 1)
                    receiptRow("Distance / Time", "\(String(format: "%.1f", receipt.distanceMiles)) mi • \(Int(receipt.durationMinutes)) min")

                    Divider()

                    receiptAmountRow("Total", receipt.fare, isTotal: true)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Charge breakdown")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)

                        ForEach(receipt.chargeBreakdown.lineItems) { item in
                            receiptAmountRow(item.title, item.amount)
                        }
                    }

                    Divider()

                    receiptRow("Paid with", receipt.cardMasked)
                }
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 16).fill(.ultraThinMaterial))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.black.opacity(0.06), lineWidth: 1))

                Spacer(minLength: 8)
            }
            .padding()
        }
        .navigationTitle("Receipt")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func receiptRow(_ title: String, _ value: String, lineLimit: Int? = nil) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.primary)
            Spacer(minLength: 12)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .multilineTextAlignment(.trailing)
                .lineLimit(lineLimit)
                .foregroundStyle(Styles.rydrGradient)
        }
    }

    private func receiptAmountRow(_ title: String, _ amount: Double, isTotal: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
                .font(isTotal ? .headline : .subheadline)
                .fontWeight(isTotal ? .bold : .regular)
                .foregroundStyle(.primary)
            Spacer(minLength: 12)
            Text(currency(amount))
                .font(isTotal ? .headline.bold() : .subheadline.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(Styles.rydrGradient)
        }
    }

    private func currency(_ amount: Double) -> String {
        let sign = amount < 0 ? "-$" : "$"
        return sign + String(format: "%.2f", abs(amount))
    }
}

// MARK: - Rydr receipt route map
private struct RydrReceiptRouteMap: View {
    let pickup: CLLocationCoordinate2D
    let dropoff: CLLocationCoordinate2D

    var body: some View {
        Map(initialPosition: .region(fitRegion)) {
            MapPolyline(coordinates: [pickup, dropoff])
                .stroke(Styles.rydrGradient, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))

            Annotation("Pickup", coordinate: pickup, anchor: .bottom) {
                RydrReceiptRoutePin(kind: .pickup)
            }

            Annotation("Drop-off", coordinate: dropoff, anchor: .bottom) {
                RydrReceiptRoutePin(kind: .dropoff)
            }
        }
        .mapStyle(.standard(elevation: .realistic, pointsOfInterest: .excludingAll))
        .mapControlVisibility(.hidden)
        .allowsHitTesting(false)
        .overlay(alignment: .topLeading) {
            Label("Rydr Map", systemImage: "location.north.line.fill")
                .font(.caption2.weight(.black))
                .foregroundStyle(Styles.rydrGradient)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(.ultraThinMaterial, in: Capsule())
                .padding(10)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.55), lineWidth: 1)
        }
    }

    private var fitRegion: MKCoordinateRegion {
        let minLat = min(pickup.latitude, dropoff.latitude)
        let maxLat = max(pickup.latitude, dropoff.latitude)
        let minLon = min(pickup.longitude, dropoff.longitude)
        let maxLon = max(pickup.longitude, dropoff.longitude)

        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLon + maxLon) / 2
        )
        let span = MKCoordinateSpan(
            latitudeDelta: max(0.02, (maxLat - minLat) * 1.6),
            longitudeDelta: max(0.02, (maxLon - minLon) * 1.6)
        )
        return MKCoordinateRegion(center: center, span: span)
    }
}

private enum RydrReceiptRoutePinKind {
    case pickup
    case dropoff

    var title: String {
        switch self {
        case .pickup: return "Pickup"
        case .dropoff: return "Drop-off"
        }
    }

    var icon: String {
        switch self {
        case .pickup: return "figure.wave"
        case .dropoff: return "flag.checkered"
        }
    }
}

private struct RydrReceiptRoutePin: View {
    let kind: RydrReceiptRoutePinKind

    var body: some View {
        VStack(spacing: 3) {
            ZStack {
                Circle()
                    .fill(kind == .pickup ? AnyShapeStyle(Color(.systemBackground)) : AnyShapeStyle(Styles.rydrGradient))
                    .frame(width: 34, height: 34)
                    .overlay(Circle().stroke(Color.white, lineWidth: 3))
                    .shadow(color: Color.black.opacity(0.16), radius: 8, y: 4)

                Image(systemName: kind.icon)
                    .font(.system(size: 14, weight: .black))
                    .foregroundStyle(kind == .pickup ? Color.red : Color.white)
            }

            Text(kind.title)
                .font(.caption2.weight(.black))
                .foregroundStyle(.primary)
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(.ultraThinMaterial, in: Capsule())
        }
        .accessibilityLabel(kind.title)
    }
}

// MARK: - Minimal coordinate fallback (keeps things working without geocoding)
private func pseudoCoord(from text: String) -> CLLocationCoordinate2D {
    // Base around Atlanta; jitter deterministically from the string
    let base = CLLocationCoordinate2D(latitude: 33.7490, longitude: -84.3880)
    let h = abs(text.hashValue)
    let lat = base.latitude  + Double(h % 200 - 100) / 10000.0
    let lon = base.longitude + Double((h / 200) % 200 - 100) / 10000.0
    return CLLocationCoordinate2D(latitude: lat, longitude: lon)
}
