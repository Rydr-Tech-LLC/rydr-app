//
//  DriverCardView.swift
//  RydrPlayground
//
//  Created by Khris Nunnally on 6/21/25.
//
import SwiftUI

/// Swipeable tile showing a single driver with image, rating, car, compliments,
/// and a price that honors the selected ride tier caps + booking fee.
struct DriverCardView: View {
    let driver: Driver
    var estimate: RideEstimate = .init(distanceMiles: 6.2, durationMinutes: 18) // fallback if host doesn't pass one
    var rideType: String = "Rydr Go"                                            // fallback if host doesn't pass one
    var onConfirm: () -> Void

    private var pricingConfig: RideTierPricing {
        RideManager.pricingConfig(for: rideType)
    }

    // Validated rates for this tier
    private var perMile: Double { pricingConfig.clampedPerMile(driver.perMile) }
    private var perMinute: Double { pricingConfig.clampedPerMinute(driver.perMinute) }

    // Estimated fare (booking fee + time + distance)
    private var fareBreakdown: RideFareBreakdown {
        RideManager.fareBreakdown(estimate: estimate, with: driver, rideType: rideType)
    }

    private var price: Double {
        fareBreakdown.finalRiderTotal
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            // Card background
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(Color.black.opacity(0.08), lineWidth: 1)
                )

            VStack(alignment: .leading, spacing: 14) {

                // Top row: avatar + name/rating + price
                HStack(alignment: .center, spacing: 12) {
                    avatar
                    VStack(alignment: .leading, spacing: 2) {
                        Text(driver.name).font(.headline)
                        HStack(spacing: 6) {
                            Image(systemName: "star.fill").font(.caption2).foregroundStyle(.yellow)
                            Text(String(format: "%.1f", driver.rating))
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()

                    // Big price in top right
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("$\(price, specifier: "%.2f")")
                            .font(.title3.bold())
                            .monospacedDigit()
                        Text(pricingConfig.title)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                // Car image (if any)
                if let imgName = driver.carImage, !imgName.isEmpty, UIImage(named: imgName) != nil {
                    Image(imgName)
                        .resizable()
                        .scaledToFill()
                        .frame(height: 140)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(Color.black.opacity(0.06), lineWidth: 1)
                        )
                } else {
                    ZStack {
                        RoundedRectangle(cornerRadius: 14).fill(.thinMaterial)
                        HStack(spacing: 8) {
                            Image(systemName: "car.fill")
                            Text(driver.carMakeModel)
                        }
                        .foregroundStyle(.secondary)
                    }
                    .frame(height: 90)
                }

                // Car details + estimate snippet
                VStack(alignment: .leading, spacing: 4) {
                    Text(driver.carMakeModel)
                        .font(.subheadline).foregroundStyle(.primary)
                    Text("\(String(format: "%.1f", estimate.distanceMiles)) mi • \(Int(estimate.durationMinutes)) min")
                        .font(.caption).foregroundStyle(.secondary)
                }

                // Compliment chips (if any)
                if !driver.compliments.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(driver.compliments.prefix(6), id: \.self) { c in
                                Text(c)
                                    .font(.caption)
                                    .padding(.vertical, 6).padding(.horizontal, 10)
                                    .background(
                                        Capsule().fill(Color.blue.opacity(0.10))
                                    )
                                    .overlay(
                                        Capsule().stroke(Color.blue.opacity(0.15), lineWidth: 1)
                                    )
                            }
                        }
                    }
                }

                // Rate breakdown row (small print)
                HStack(spacing: 10) {
                    label(value: fareBreakdown.bookingFee, unit: "booking")
                    Divider().frame(height: 14)
                    label(value: perMile, unit: "/mi")
                    label(value: perMinute, unit: "/min")
                    Spacer()
                }
                .font(.caption2)
                .foregroundStyle(.secondary)

                if fareBreakdown.minimumFareAdjustment > 0 {
                    HStack {
                        Text("Minimum Fare Adjustment")
                        Spacer()
                        Text("$\(fareBreakdown.minimumFareAdjustment, specifier: "%.2f")")
                            .monospacedDigit()
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }

                // Confirm CTA
                Button {
                    onConfirm()
                } label: {
                    Text("Confirm ride with \(driver.name)")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(16)
        }
        .frame(maxWidth: .infinity, minHeight: 360) // good “card” height for pager
        .padding(.horizontal)
    }

    // MARK: - Pieces

    @ViewBuilder private var avatar: some View {
        if let imgName = driver.profileImage, !imgName.isEmpty, UIImage(named: imgName) != nil {
            Image(imgName)
                .resizable()
                .scaledToFill()
                .frame(width: 48, height: 48)
                .clipShape(Circle())
        } else {
            Circle()
                .fill(.gray.opacity(0.2))
                .frame(width: 48, height: 48)
                .overlay(Text(String(driver.name.prefix(1))).font(.headline))
        }
    }

    private func label(value: Double, unit: String) -> some View {
        HStack(spacing: 2) {
            Text("$\(value, specifier: "%.2f")")
            Text(unit)
        }
    }
}
