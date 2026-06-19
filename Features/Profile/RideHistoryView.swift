//
//  RideHistoryView.swift
//  RydrPlayground
//
//  Created by Khris Nunnally on 8/24/25.
//


import SwiftUI
import MapKit
import UIKit

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

    private var totalSpent: Double {
        filtered.reduce(0) { $0 + $1.fare }
    }

    private var totalDistance: Double {
        filtered.reduce(0) { $0 + $1.distanceMiles }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                header

                if filtered.isEmpty {
                    ContentUnavailableView("No rides in this range", systemImage: "clock.arrow.circlepath",
                                           description: Text("Choose a wider range to see more."))
                        .padding(.top, 40)
                } else {
                    VStack(spacing: 12) {
                        ForEach(filtered) { r in
                            NavigationLink {
                                RideReceiptDetailView(receipt: r)
                            } label: {
                                RideHistoryCard(receipt: r)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 16)
                }
            }
            .padding(.top, 12)
            .navigationTitle("Ride History")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Ride History")
                    .font(.title2.weight(.black))
                Text("Your completed rides at a glance.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 6) {
                ForEach(Window.allCases) { w in
                    Button {
                        withAnimation(.snappy(duration: 0.25)) { window = w }
                    } label: {
                        Text(w.rawValue)
                            .font(.subheadline.weight(.bold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                            .foregroundStyle(window == w ? Color.white : Color.secondary)
                            .background {
                                if window == w {
                                    Capsule().fill(Styles.rydrGradient)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(4)
            .background(Capsule().fill(Color(.secondarySystemGroupedBackground)))

            HStack(spacing: 10) {
                RideHistoryStatTile(icon: "car.fill", tint: .red, value: "\(filtered.count)", label: "Rides")
                RideHistoryStatTile(icon: "dollarsign.circle.fill", tint: .green, value: totalSpent.formatted(.currency(code: "USD")), label: "Total Spent")
                RideHistoryStatTile(icon: "road.lanes", tint: .blue, value: "\(Int(totalDistance)) mi", label: "Distance")
            }
        }
        .rideHistoryPremiumCard()
        .padding(.horizontal)
    }
}

// MARK: - Stat tile
private struct RideHistoryStatTile: View {
    let icon: String
    let tint: Color
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle().fill(tint.opacity(0.14)).frame(width: 36, height: 36)
                Image(systemName: icon).font(.subheadline.weight(.semibold)).foregroundStyle(tint)
            }
            Text(value)
                .font(.subheadline.weight(.black))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Static map snapshot thumbnail
private final class RideHistorySnapshotCache {
    static let shared = RideHistorySnapshotCache()
    private let cache = NSCache<NSString, UIImage>()

    func image(for key: String) -> UIImage? { cache.object(forKey: key as NSString) }
    func store(_ image: UIImage, for key: String) { cache.setObject(image, forKey: key as NSString) }
}

private struct RideHistoryMapThumbnail: View {
    let pickup: CLLocationCoordinate2D
    let dropoff: CLLocationCoordinate2D
    let cacheKey: String

    @State private var snapshotImage: UIImage?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))

            if let snapshotImage {
                Image(uiImage: snapshotImage)
                    .resizable()
                    .scaledToFill()
            } else {
                ProgressView()
                    .controlSize(.mini)
            }
        }
        .frame(width: 84, height: 100)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .task(id: cacheKey) {
            await loadSnapshot()
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
            latitudeDelta: max(0.015, (maxLat - minLat) * 1.8),
            longitudeDelta: max(0.015, (maxLon - minLon) * 1.8)
        )
        return MKCoordinateRegion(center: center, span: span)
    }

    @MainActor
    private func loadSnapshot() async {
        if let cached = RideHistorySnapshotCache.shared.image(for: cacheKey) {
            snapshotImage = cached
            return
        }

        let options = MKMapSnapshotter.Options()
        options.region = fitRegion
        options.size = CGSize(width: 168, height: 200)
        options.scale = UIScreen.main.scale
        options.showsBuildings = false
        options.pointOfInterestFilter = .excludingAll
        options.mapType = .mutedStandard

        guard let snapshot = try? await MKMapSnapshotter(options: options).start() else { return }

        let rendered = drawRoute(on: snapshot)
        RideHistorySnapshotCache.shared.store(rendered, for: cacheKey)
        snapshotImage = rendered
    }

    private func drawRoute(on snapshot: MKMapSnapshotter.Snapshot) -> UIImage {
        let image = snapshot.image
        let renderer = UIGraphicsImageRenderer(size: image.size)

        return renderer.image { ctx in
            image.draw(at: .zero)

            let pickupPoint = snapshot.point(for: pickup)
            let dropoffPoint = snapshot.point(for: dropoff)
            let midPoint = CGPoint(
                x: (pickupPoint.x + dropoffPoint.x) / 2,
                y: min(pickupPoint.y, dropoffPoint.y) - 14
            )

            let path = UIBezierPath()
            path.move(to: pickupPoint)
            path.addQuadCurve(to: dropoffPoint, controlPoint: midPoint)

            UIColor.white.withAlphaComponent(0.9).setStroke()
            path.lineWidth = 6
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            path.stroke()

            UIColor.systemRed.setStroke()
            path.lineWidth = 3.5
            path.stroke()

            let dotRadius: CGFloat = 5
            ctx.cgContext.setFillColor(UIColor.white.cgColor)
            ctx.cgContext.fillEllipse(in: CGRect(x: pickupPoint.x - dotRadius - 1.5, y: pickupPoint.y - dotRadius - 1.5, width: (dotRadius + 1.5) * 2, height: (dotRadius + 1.5) * 2))
            ctx.cgContext.fillEllipse(in: CGRect(x: dropoffPoint.x - dotRadius - 1.5, y: dropoffPoint.y - dotRadius - 1.5, width: (dotRadius + 1.5) * 2, height: (dotRadius + 1.5) * 2))

            ctx.cgContext.setFillColor(UIColor.systemRed.cgColor)
            ctx.cgContext.fillEllipse(in: CGRect(x: pickupPoint.x - dotRadius, y: pickupPoint.y - dotRadius, width: dotRadius * 2, height: dotRadius * 2))

            ctx.cgContext.setFillColor(UIColor.systemGreen.cgColor)
            ctx.cgContext.fillEllipse(in: CGRect(x: dropoffPoint.x - dotRadius, y: dropoffPoint.y - dotRadius, width: dotRadius * 2, height: dotRadius * 2))
        }
    }
}

// MARK: - Ride card
private struct RideHistoryCard: View {
    let receipt: Receipt

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            RideHistoryMapThumbnail(
                pickup: pseudoCoord(from: receipt.pickup),
                dropoff: pseudoCoord(from: receipt.dropoff),
                cacheKey: receipt.rideId.uuidString
            )

            VStack(alignment: .leading, spacing: 6) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(short(receipt.pickup))
                        .font(.subheadline.weight(.bold))
                        .lineLimit(1)
                    Text(short(receipt.dropoff))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                HStack(spacing: 5) {
                    Image(systemName: "calendar")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(receipt.date.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text("•")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Image(systemName: "clock")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(receipt.date.formatted(date: .omitted, time: .shortened))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 6) {
                    RideHistoryAvatar(name: receipt.driverName, size: 24)
                    Text(receipt.driverName)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 8) {
                Text("$" + String(format: "%.2f", receipt.fare))
                    .font(.headline.weight(.black))
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(14)
        .rideHistoryPremiumCard()
    }

    private func short(_ s: String) -> String {
        s.split(separator: ",").first.map(String.init) ?? s
    }
}

private struct RideHistoryAvatar: View {
    let name: String
    var size: CGFloat = 42

    var body: some View {
        Text(String(name.trimmingCharacters(in: .whitespacesAndNewlines).first ?? "R"))
            .font(.system(size: size * 0.38, weight: .black))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Circle().fill(Styles.rydrGradient))
    }
}

private extension View {
    func rideHistoryPremiumCard() -> some View {
        self
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color(.systemBackground))
                    .shadow(color: Color.black.opacity(0.06), radius: 18, y: 8)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color.black.opacity(0.05), lineWidth: 1)
            )
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
                .stroke(Color.black.opacity(0.14), style: StrokeStyle(lineWidth: 10, lineCap: .round, lineJoin: .round))

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
