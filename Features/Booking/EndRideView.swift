//
//  EndRideView.swift
//  RydrPlayground
//
//  Created by Khris Nunnally on 8/29/25.
//
import SwiftUI

struct EndRideView: View {
    let ride: Receipt?
    let onDone: () -> Void
    var onTipSelected: (Int) -> Void = { _ in }
    /// The receipt screen observes `paymentStatus`/`paymentFailureReason`
    /// and shows a "Payment Failed" card with a Retry action instead of
    /// pretending the charge went through. Defaults to a fresh, disconnected
    /// instance (paymentStatus == nil, card hidden) for legacy/preview call
    /// sites that don't have a live RideManager on hand — `@ObservedObject`
    /// requires a non-optional ObservableObject, so this is the cleanest way
    /// to keep the parameter optional in spirit without breaking observation.
    @ObservedObject var rideManager: RideManager = RideManager()

    @State private var phase: CompletionPhase = .rateAndTip
    @State private var rating: Int = 0
    @State private var selectedCompliments: Set<String> = []
    @State private var selectedTip: Int = 0
    @State private var extraNotes: String = ""
    @State private var isFavoriteDriver = false

    private let complimentSet: [RideCompliment] = [
        .init(title: "Clean car", icon: "car.fill"),
        .init(title: "Friendly", icon: "face.smiling"),
        .init(title: "Great service", icon: "heart.fill"),
        .init(title: "Excellent navigation", icon: "location.north.fill"),
        .init(title: "Smooth driving", icon: "steeringwheel"),
        .init(title: "Great conversation", icon: "message.fill")
    ]
    private let tipOptions: [Int] = [0, 200, 500, 1000]

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 18) {
                    switch phase {
                    case .rateAndTip:
                        rateAndTipContent
                    case .receipt:
                        receiptContent
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 14)
                .padding(.bottom, 30)
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(phase == .receipt ? "Done" : "Skip") {
                        if phase == .receipt {
                            onDone()
                        } else {
                            submitFeedback()
                        }
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var rateAndTipContent: some View {
        VStack(spacing: 18) {
            completionHero(
                title: "Trip complete!",
                subtitle: "Thanks for riding with Rydr.",
                tint: .green
            )

            driverSummaryCard
            ratingCard
            tipCard
            complimentsCard
            favoriteDriverCard
            feedbackCard

            Button(action: submitFeedback) {
                Text("Submit")
                    .font(.headline.weight(.bold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(EndRideGradientButton())

            safetyNote
        }
    }

    private var receiptContent: some View {
        VStack(spacing: 18) {
            completionHero(
                title: "Thanks for riding!",
                subtitle: "Your trip receipt is ready.",
                tint: .green
            )

            paymentStatusCard
            receiptCard
            driverSummaryCard
            receiptActions
            rewardsCard

            Button(action: onDone) {
                Text("Done")
                    .font(.headline.weight(.bold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(EndRideGradientButton())
        }
    }

    private func completionHero(title: String, subtitle: String, tint: Color) -> some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(tint.opacity(0.12))
                    .frame(width: 74, height: 74)
                Circle()
                    .fill(tint)
                    .frame(width: 48, height: 48)
                    .shadow(color: tint.opacity(0.28), radius: 14, y: 8)
                Image(systemName: "checkmark")
                    .font(.title2.weight(.black))
                    .foregroundStyle(.white)
            }
            .padding(.top, 10)

            Text(title)
                .font(.title2.weight(.black))
                .foregroundStyle(.primary)
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .overlay(alignment: .top) {
            ConfettiDots()
                .frame(height: 82)
                .allowsHitTesting(false)
        }
    }

    private var driverSummaryCard: some View {
        HStack(spacing: 12) {
            driverAvatar

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 5) {
                    Text(displayReceipt?.driverName ?? "Your driver")
                        .font(.headline.weight(.black))
                    Image(systemName: "checkmark.seal.fill")
                        .font(.caption)
                        .foregroundStyle(.blue)
                }
                Text("Rydr verified driver")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let displayReceipt {
                    Text("\(String(format: "%.1f", displayReceipt.distanceMiles)) mi • \(Int(displayReceipt.durationMinutes)) min")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 5) {
                Text(currency(displayReceipt?.fare ?? 0))
                    .font(.headline.weight(.black))
                    .monospacedDigit()
                Text("Completed")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.green)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Color.green.opacity(0.10)))
            }
        }
        .cardStyle()
    }

    private var driverAvatar: some View {
        Circle()
            .fill(Color(.secondarySystemGroupedBackground))
            .overlay(
                Text(String((displayReceipt?.driverName ?? "R").prefix(1)))
                    .font(.title3.weight(.black))
            )
            .frame(width: 58, height: 58)
            .overlay(Circle().stroke(Styles.rydrGradient, lineWidth: 3))
    }

    private var ratingCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("How was your ride?")
                    .font(.headline.weight(.black))
                Text("Your feedback helps keep Rydr excellent.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 14) {
                ForEach(1...5, id: \.self) { star in
                    Button {
                        withAnimation(.spring(response: 0.22, dampingFraction: 0.75)) {
                            rating = star
                        }
                    } label: {
                        Image(systemName: star <= rating ? "star.fill" : "star")
                            .font(.system(size: 34, weight: .regular))
                            .foregroundStyle(star <= rating ? Styles.rydrGradient : LinearGradient(colors: [.red], startPoint: .leading, endPoint: .trailing))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(star) star rating")
                }
            }
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .contain)
        }
        .cardStyle()
    }

    private var tipCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Tip your driver")
                        .font(.headline.weight(.black))
                    Text("100% of your tip goes to your driver.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if selectedTip > 0 {
                    Text("+\(currency(Double(selectedTip) / 100.0))")
                        .font(.subheadline.weight(.black))
                        .foregroundStyle(Styles.rydrGradient)
                        .monospacedDigit()
                }
            }

            HStack(spacing: 8) {
                ForEach(tipOptions, id: \.self) { cents in
                    tipButton(cents)
                }
            }
        }
        .cardStyle()
    }

    private func tipButton(_ cents: Int) -> some View {
        let isSelected = selectedTip == cents
        return Button {
            withAnimation(.spring(response: 0.22, dampingFraction: 0.8)) {
                selectedTip = cents
            }
        } label: {
            Text(cents == 0 ? "No tip" : "$\(cents / 100)")
                .font(.caption.weight(.bold))
                .foregroundStyle(isSelected ? Styles.rydrGradient : LinearGradient(colors: [.primary], startPoint: .leading, endPoint: .trailing))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(isSelected ? Color.red.opacity(0.08) : Color(.secondarySystemGroupedBackground))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(isSelected ? Color.red.opacity(0.45) : Color.black.opacity(0.05), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    private var complimentsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("What did you love?")
                    .font(.headline.weight(.black))
                Text("Select all that apply.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(complimentSet) { compliment in
                    complimentButton(compliment)
                }
            }
        }
        .cardStyle()
    }

    private func complimentButton(_ compliment: RideCompliment) -> some View {
        let isSelected = selectedCompliments.contains(compliment.title)
        return Button {
            withAnimation(.easeInOut(duration: 0.16)) {
                if isSelected {
                    selectedCompliments.remove(compliment.title)
                } else {
                    selectedCompliments.insert(compliment.title)
                }
            }
        } label: {
            Label(compliment.title, systemImage: compliment.icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(isSelected ? Styles.rydrGradient : LinearGradient(colors: [.primary], startPoint: .leading, endPoint: .trailing))
                .lineLimit(1)
                .minimumScaleFactor(0.82)
                .frame(maxWidth: .infinity, minHeight: 44)
                .padding(.horizontal, 8)
                .background(
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .fill(isSelected ? Color.red.opacity(0.08) : Color(.secondarySystemGroupedBackground))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .stroke(isSelected ? Color.red.opacity(0.35) : Color.black.opacity(0.05), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    private var favoriteDriverCard: some View {
        Button {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.78)) {
                isFavoriteDriver.toggle()
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: isFavoriteDriver ? "heart.fill" : "heart")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(isFavoriteDriver ? Styles.rydrGradient : LinearGradient(colors: [.secondary], startPoint: .leading, endPoint: .trailing))
                    .frame(width: 42, height: 42)
                    .background(Circle().fill(Color.red.opacity(0.08)))

                VStack(alignment: .leading, spacing: 3) {
                    Text(isFavoriteDriver ? "Favorite driver added" : "Add as favorite driver")
                        .font(.subheadline.weight(.black))
                        .foregroundStyle(.primary)
                    Text(isFavoriteDriver ? "You can find this driver faster next time." : "Save this driver for future ride preferences.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .cardStyle()
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isFavoriteDriver ? "Remove favorite driver" : "Add favorite driver")
    }

    private var feedbackCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Any additional comments?")
                .font(.headline.weight(.black))
            TextEditor(text: $extraNotes)
                .frame(minHeight: 96)
                .padding(8)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(alignment: .topLeading) {
                    if extraNotes.isEmpty {
                        Text("Share your thoughts. Optional.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 16)
                            .allowsHitTesting(false)
                    }
                }
        }
        .cardStyle()
    }

    @ViewBuilder
    private var paymentStatusCard: some View {
        if rideManager.paymentStatus == "failed" {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(Color.red.opacity(0.12))
                            .frame(width: 42, height: 42)
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.headline.weight(.bold))
                            .foregroundStyle(.red)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Payment failed")
                            .font(.headline.weight(.black))
                            .foregroundStyle(.primary)
                        Text(rideManager.paymentFailureReason ?? "We couldn't charge your card for this ride.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }

                HStack(spacing: 10) {
                    Button {
                        retryPayment()
                    } label: {
                        if rideManager.isRetryingPayment {
                            ProgressView().tint(.white)
                        } else {
                            Text("Retry Payment")
                        }
                    }
                    .font(.subheadline.weight(.bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(Color.red, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .foregroundStyle(.white)
                    .disabled(rideManager.isRetryingPayment)

                    NavigationLink {
                        PaymentMethodView()
                    } label: {
                        Text("Update Card")
                            .font(.subheadline.weight(.bold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 11)
                            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .foregroundStyle(.primary)
                    }
                }
            }
            .padding(14)
            .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color.red.opacity(0.25), lineWidth: 1)
            )
        } else if rideManager.paymentStatus == "processing" {
            HStack(spacing: 12) {
                ProgressView()
                VStack(alignment: .leading, spacing: 2) {
                    Text("Finishing up payment…")
                        .font(.subheadline.weight(.semibold))
                    Text("This usually only takes a few seconds.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .cardStyle()
        }
    }

    private func retryPayment() {
        guard let receipt = displayReceipt, let backendRideId = receipt.backendRideId else { return }
        Task {
            await rideManager.retryFailedPayment(rideId: backendRideId)
        }
    }

    private var receiptCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Receipt")
                    .font(.headline.weight(.black))
                Spacer()
                Text("Completed")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.green)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Color.green.opacity(0.10)))
            }

            if let displayReceipt {
                receiptRow("Driver", displayReceipt.driverName)
                receiptRow("Date", displayReceipt.date.formatted(date: .abbreviated, time: .shortened))
                receiptRow("Route", "\(displayReceipt.pickup) → \(displayReceipt.dropoff)", lineLimit: 2)
                receiptRow("Distance / Time", "\(String(format: "%.1f", displayReceipt.distanceMiles)) mi • \(Int(displayReceipt.durationMinutes)) min")

                Divider()

                HStack(alignment: .firstTextBaseline) {
                    Text("Total")
                        .font(.headline.weight(.black))
                    Spacer()
                    Text(currency(displayReceipt.fare))
                        .font(.title3.weight(.black))
                        .foregroundStyle(Styles.rydrGradient)
                        .monospacedDigit()
                }

                VStack(alignment: .leading, spacing: 9) {
                    Text("Charge breakdown")
                        .font(.subheadline.weight(.black))
                    ForEach(displayReceipt.chargeBreakdown.lineItems) { item in
                        receiptAmountRow(item.title, item.amount)
                    }
                }

                Divider()
                receiptRow("Paid with", displayReceipt.cardMasked)
            } else {
                Text("Receipt details are not available for this test ride.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .cardStyle()
    }

    private var receiptActions: some View {
        HStack(spacing: 12) {
            receiptAction("Message", icon: "message.fill")
            receiptAction("Issue", icon: "exclamationmark.triangle.fill")
            receiptAction("Activity", icon: "clock.arrow.circlepath")
        }
    }

    private func receiptAction(_ title: String, icon: String) -> some View {
        Button {} label: {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.subheadline.weight(.bold))
                    .frame(width: 42, height: 42)
                    .background(Circle().fill(Color(.systemBackground)))
                    .shadow(color: .black.opacity(0.06), radius: 8, y: 4)
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }

    private var rewardsCard: some View {
        HStack(spacing: 12) {
            Image(systemName: "gift.fill")
                .font(.title3.weight(.bold))
                .foregroundStyle(.green)
                .frame(width: 48, height: 48)
                .background(Circle().fill(Color.green.opacity(0.12)))

            VStack(alignment: .leading, spacing: 3) {
                Text("RydrBank rewards")
                    .font(.subheadline.weight(.black))
                Text("Eligible ride progress has been recorded.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(14)
        .background(Color.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color.green.opacity(0.12), lineWidth: 1))
    }

    private var safetyNote: some View {
        HStack(spacing: 12) {
            Image(systemName: "shield.checkered")
                .font(.headline.weight(.bold))
                .foregroundStyle(Styles.rydrGradient)
                .frame(width: 42, height: 42)
                .background(Circle().fill(Color.red.opacity(0.08)))
            VStack(alignment: .leading, spacing: 3) {
                Text("Your safety and feedback help us improve.")
                    .font(.subheadline.weight(.semibold))
                Text("Trip issues can be reviewed from Activity after this step.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .cardStyle()
    }

    private var displayReceipt: Receipt? {
        ride?.addingTip(cents: selectedTip)
    }

    private func submitFeedback() {
        onTipSelected(selectedTip)
        withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
            phase = .receipt
        }
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

    private func receiptAmountRow(_ title: String, _ amount: Double) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.primary)
            Spacer(minLength: 12)
            Text(currency(amount))
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(Styles.rydrGradient)
        }
    }

    private func currency(_ amount: Double) -> String {
        let sign = amount < 0 ? "-$" : "$"
        return sign + String(format: "%.2f", abs(amount))
    }
}

private enum CompletionPhase {
    case rateAndTip
    case receipt
}

private struct RideCompliment: Identifiable {
    let id = UUID()
    let title: String
    let icon: String
}

private struct EndRideGradientButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.vertical, 16)
            .foregroundStyle(.white)
            .background(Styles.rydrGradient)
            .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
            .shadow(color: Color.red.opacity(configuration.isPressed ? 0.10 : 0.22), radius: 16, y: 10)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
    }
}

private struct ConfettiDots: View {
    private let dots: [(x: CGFloat, y: CGFloat, color: Color)] = [
        (0.10, 0.30, .blue), (0.18, 0.12, .green), (0.28, 0.36, .orange),
        (0.38, 0.16, .red), (0.52, 0.32, .purple), (0.64, 0.10, .green),
        (0.74, 0.28, .blue), (0.86, 0.16, .orange), (0.92, 0.38, .red)
    ]

    var body: some View {
        GeometryReader { proxy in
            ForEach(dots.indices, id: \.self) { index in
                let dot = dots[index]
                Circle()
                    .fill(dot.color.opacity(0.85))
                    .frame(width: 4, height: 4)
                    .position(x: proxy.size.width * dot.x, y: proxy.size.height * dot.y)
            }
        }
    }
}

private extension View {
    func cardStyle() -> some View {
        self
            .padding(14)
            .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color.black.opacity(0.06), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.05), radius: 14, y: 8)
    }
}
