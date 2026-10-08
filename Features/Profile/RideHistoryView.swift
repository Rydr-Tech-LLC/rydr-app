//
//  RideHistoryView.swift
//  RydrPlayground
//
//  Created by Khris Nunnally on 8/24/25.
//


import SwiftUI

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

// MARK: - Ride card
private struct RideHistoryCard: View {
    let receipt: Receipt

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "point.bottomleft.forward.to.point.topright.scurvepath.fill")
                .font(.title2.weight(.bold))
                .foregroundStyle(Styles.rydrGradient)
                .frame(width: 84, height: 100)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

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
                VStack(alignment: .leading, spacing: 12) {
                    Label(receipt.pickup, systemImage: "circle.circle.fill")
                    Label(receipt.dropoff, systemImage: "mappin.circle.fill")
                }
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(18)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))

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
