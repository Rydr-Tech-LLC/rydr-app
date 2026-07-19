import SwiftUI
import Combine
import CoreLocation
import FirebaseFirestore
import MapKit

enum DriverDashboardSheet: Identifiable {
    case fareInsights
    case rideFilters
    case rideType(String)
    case menu(SideMenuItem)

    var id: String {
        switch self {
        case .fareInsights: return "fareInsights"
        case .rideFilters: return "rideFilters"
        case .rideType(let rideType): return "rideType-\(rideType)"
        case .menu(let item): return "menu-\(item.rawValue)"
        }
    }
}

struct RideTypeConfigurationView: View {
    let rideType: String
    let isOnline: Bool
    let isEligible: Bool
    let isSelected: Bool
    let hasSavedRate: Bool
    let rate: DriverRateSetting
    let onToggle: () -> Void
    let onSaveRate: (Double, Double) -> Void

    @State private var draftPerMile: Double?
    @State private var draftPerMinute: Double?
    @State private var perMileText: String = ""
    @State private var perMinuteText: String = ""

    private var pricing: RydrDriverTierPricing {
        RydrRideTierCatalog.pricing(for: rideType)
    }

    private var currentPerMile: Double {
        draftPerMile ?? rate.perMile
    }

    private var currentPerMinute: Double {
        draftPerMinute ?? rate.perMinute
    }

    private var hasDraftChanges: Bool {
        abs(currentPerMile - rate.perMile) > 0.001 || abs(currentPerMinute - rate.perMinute) > 0.001
    }

    private var isPerMileInputValid: Bool {
        isValidRateText(perMileText, bounds: pricing.minPerMile...pricing.maxPerMile)
    }

    private var isPerMinuteInputValid: Bool {
        isValidRateText(perMinuteText, bounds: pricing.minPerMinute...pricing.maxPerMinute)
    }

    private var canSaveRate: Bool {
        !isOnline && isEligible && hasDraftChanges && isPerMileInputValid && isPerMinuteInputValid
    }

    private var suggestedPerMile: Double {
        suggestedRate(min: pricing.minPerMile, max: pricing.maxPerMile)
    }

    private var suggestedPerMinute: Double {
        suggestedRate(min: pricing.minPerMinute, max: pricing.maxPerMinute)
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 18) {
                    Capsule()
                        .fill(Color(.systemGray4))
                        .frame(width: 48, height: 5)
                        .padding(.top, 4)

                    rideTypeHeroCard
                    availabilityCard
                    currentRatesCard
                    requirementsCard
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 28)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Ride Type")
            .navigationBarTitleDisplayMode(.inline)
        }
        .onAppear {
            resetDrafts()
        }
        .onChange(of: rideType) { _, _ in
            resetDrafts()
        }
        .onChange(of: rate.perMile) { _, _ in
            resetDrafts()
        }
        .onChange(of: rate.perMinute) { _, _ in
            resetDrafts()
        }
    }

    private var rideTypeHeroCard: some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.white.opacity(0.92))
                    .shadow(color: Color.red.opacity(0.12), radius: 12, y: 7)
                Image(systemName: icon)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(Color.red)
            }
            .frame(width: 66, height: 66)

            VStack(alignment: .leading, spacing: 5) {
                Text(pricing.title)
                    .font(.title.weight(.heavy))
                    .foregroundStyle(.primary)
                Text(pricing.purpose)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white,
                            Color(red: 1.0, green: 0.93, blue: 0.93),
                            Color.red.opacity(0.22)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .overlay(alignment: .trailing) {
                    Circle()
                        .fill(Styles.rydrGradient.opacity(0.30))
                        .frame(width: 170, height: 170)
                        .offset(x: 82, y: 38)
                }
                .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .stroke(Color.red.opacity(0.14), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.08), radius: 18, y: 10)
        )
    }

    private var availabilityCard: some View {
        HStack(spacing: 14) {
            Image(systemName: isEligible ? "checkmark.shield.fill" : "lock.shield.fill")
                .font(.title2.weight(.semibold))
                .foregroundStyle(isEligible ? Color.green : Color.orange)
                .frame(width: 48, height: 48)
                .background(Circle().fill((isEligible ? Color.green : Color.orange).opacity(0.12)))

            VStack(alignment: .leading, spacing: 3) {
                Text("Availability")
                    .font(.headline.weight(.bold))
                Text(isEligible ? "Approved for this ride type." : lockedMessage)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                onToggle()
            } label: {
                HStack(spacing: 6) {
                    Circle()
                        .fill(isSelected ? Color.green : Color.secondary)
                        .frame(width: 7, height: 7)
                    Text(isSelected ? "Active" : "Paused")
                }
                .font(.subheadline.weight(.bold))
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(Capsule().fill(isSelected ? Color.green.opacity(0.16) : Color(.systemGray5)))
                .foregroundStyle(isSelected ? .green : .secondary)
            }
            .disabled(!isEligible)
        }
        .padding(18)
        .background(cardBackground(cornerRadius: 24))
    }

    private var currentRatesCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Current Rates")
                    .font(.title3.weight(.heavy))
                Spacer()
                Label(rateStatusText, systemImage: rateStatusIcon)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(rateStatusColor)
            }

            rateRow(
                title: "Per Mile",
                range: pricing.perMileRangeText,
                icon: "speedometer",
                value: currentPerMile,
                text: $perMileText,
                isInputValid: isPerMileInputValid,
                bounds: pricing.minPerMile...pricing.maxPerMile,
                suggested: suggestedPerMile,
                suggestedSuffix: "/mi",
                onTextChange: { updateRateText($0, field: .perMile) },
                onApplySuggested: { setRate(field: .perMile, value: suggestedPerMile) },
                onStep: { stepRate(field: .perMile, delta: $0) }
            )

            Divider()
                .padding(.leading, 72)

            rateRow(
                title: "Per Minute",
                range: pricing.perMinuteRangeText,
                icon: "clock",
                value: currentPerMinute,
                text: $perMinuteText,
                isInputValid: isPerMinuteInputValid,
                bounds: pricing.minPerMinute...pricing.maxPerMinute,
                suggested: suggestedPerMinute,
                suggestedSuffix: "/min",
                onTextChange: { updateRateText($0, field: .perMinute) },
                onApplySuggested: { setRate(field: .perMinute, value: suggestedPerMinute) },
                onStep: { stepRate(field: .perMinute, delta: $0) }
            )

            if hasDraftChanges {
                unsavedRateChangesNotice
            }

            Button {
                saveRateChanges()
            } label: {
                Label("Save Changes", systemImage: "checkmark.circle.fill")
                    .font(.headline.weight(.bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 17)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Styles.rydrGradient)
                            .opacity(canSaveRate ? 1 : 0.48)
                    )
                    .foregroundStyle(.white)
                    .shadow(color: canSaveRate ? Color.red.opacity(0.28) : Color.clear, radius: 16, y: 8)
            }
            .disabled(!canSaveRate)

            if isOnline {
                Label("Rates may only be adjusted while offline.", systemImage: "lock.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)
            } else if !isPerMileInputValid || !isPerMinuteInputValid {
                Label("Custom rates must stay inside the listed range and use a 0.00 format.", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)
            }
        }
        .padding(20)
        .background(cardBackground(cornerRadius: 26))
    }

    private var unsavedRateChangesNotice: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.circle.fill")
                .font(.headline.weight(.bold))
                .foregroundStyle(.orange)
                .frame(width: 34, height: 34)
                .background(Circle().fill(Color.orange.opacity(0.14)))

            VStack(alignment: .leading, spacing: 2) {
                Text("Unsaved rate changes")
                    .font(.subheadline.weight(.bold))
                Text("$\(rateText(currentPerMile))/mi · $\(rateText(currentPerMinute))/min")
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                saveRateChanges()
            } label: {
                Text("Save")
                    .font(.caption.weight(.heavy))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(Capsule().fill(canSaveRate ? Color.orange : Color(.systemGray5)))
                    .foregroundStyle(canSaveRate ? Color.white : Color.secondary)
            }
            .disabled(!canSaveRate)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.orange.opacity(0.10))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.orange.opacity(0.24), lineWidth: 1)
                )
        )
    }

    private var requirementsCard: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Requirements")
                    .font(.headline.weight(.bold))
                ForEach(requirements, id: \.self) { requirement in
                    Label(requirement, systemImage: "checkmark.circle.fill")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(Color.green, Color.green.opacity(0.14))
                }
            }
            Spacer()
            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(Styles.rydrGradient)
                .frame(width: 78, height: 78)
                .background(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(Color.red.opacity(0.08))
                )
        }
        .padding(20)
        .background(cardBackground(cornerRadius: 24))
    }

    private enum RateField {
        case perMile
        case perMinute
    }

    private func rateRow(
        title: String,
        range: String,
        icon: String,
        value: Double,
        text: Binding<String>,
        isInputValid: Bool,
        bounds: ClosedRange<Double>,
        suggested: Double,
        suggestedSuffix: String,
        onTextChange: @escaping (String) -> Void,
        onApplySuggested: @escaping () -> Void,
        onStep: @escaping (Double) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 14) {
                Image(systemName: icon)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(Color.red)
                    .frame(width: 54, height: 54)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.red.opacity(0.09))
                    )

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.headline.weight(.bold))
                    Text(range)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 8) {
                    Label("Edit rate", systemImage: "pencil")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(isOnline || !isEligible ? Color.secondary : Color.red)

                    HStack(spacing: 3) {
                        Text("$")
                            .font(.title3.weight(.heavy).monospacedDigit())
                            .foregroundStyle(isInputValid ? Color.primary : Color.red)
                        TextField(rateText(value), text: text)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .font(.title2.weight(.heavy).monospacedDigit())
                            .foregroundStyle(isInputValid ? Color.primary : Color.red)
                            .frame(width: 82)
                            .disabled(isOnline || !isEligible)
                            .onChange(of: text.wrappedValue) { _, newValue in
                                onTextChange(newValue)
                            }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color(.systemBackground))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(isInputValid ? Color.red.opacity(0.28) : Color.red.opacity(0.70), lineWidth: 1.4)
                            )
                    )

                    HStack(spacing: 0) {
                        Button {
                            onStep(-0.05)
                        } label: {
                            Image(systemName: "minus")
                                .font(.title3.weight(.bold))
                                .frame(width: 48, height: 42)
                        }
                        .disabled(isOnline || !isEligible || value <= bounds.lowerBound + 0.001)

                        Rectangle()
                            .fill(Color(.separator))
                            .frame(width: 1, height: 24)

                        Button {
                            onStep(0.05)
                        } label: {
                            Image(systemName: "plus")
                                .font(.title3.weight(.bold))
                                .frame(width: 48, height: 42)
                        }
                        .disabled(isOnline || !isEligible || value >= bounds.upperBound - 0.001)
                    }
                    .foregroundStyle(Color.red)
                    .background(Capsule().fill(Color(.systemGray6)))
                    .overlay(Capsule().stroke(Color.black.opacity(0.06), lineWidth: 1))
                }
            }

            suggestionSignalRow(
                value: value,
                suggested: suggested,
                suffix: suggestedSuffix,
                onApplySuggested: onApplySuggested
            )
        }
    }

    private func suggestionSignalRow(
        value: Double,
        suggested: Double,
        suffix: String,
        onApplySuggested: @escaping () -> Void
    ) -> some View {
        let signal = suggestionSignal(current: value, suggested: suggested)
        return HStack(spacing: 12) {
            Image(systemName: signal.icon)
                .font(.headline.weight(.bold))
                .foregroundStyle(signal.color)
                .frame(width: 34, height: 34)
                .background(Circle().fill(signal.color.opacity(0.12)))

            VStack(alignment: .leading, spacing: 2) {
                Text(signal.title)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.primary)
                Text("Suggested $\(rateText(suggested))\(suffix)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Button {
                onApplySuggested()
            } label: {
                Text("Apply")
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(Color.red.opacity(0.12)))
                    .foregroundStyle(Color.red)
            }
            .disabled(isOnline || !isEligible || abs(value - suggested) < 0.001)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.systemGray6))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(signal.color.opacity(0.18), lineWidth: 1)
                )
        )
    }

    private func suggestionSignal(current: Double, suggested: Double) -> (title: String, icon: String, color: Color) {
        if suggested > current + 0.001 {
            return ("Demand supports increasing", "chart.line.uptrend.xyaxis", Color.red)
        }
        if suggested < current - 0.001 {
            return ("Signal suggests easing down", "chart.line.downtrend.xyaxis", Color.secondary)
        }
        return ("Rate is on target", "checkmark.circle.fill", Color.green)
    }

    private func updateRateText(_ text: String, field: RateField) {
        switch field {
        case .perMile:
            guard let value = parsedRate(text), (pricing.minPerMile...pricing.maxPerMile).contains(value) else { return }
            draftPerMile = roundToCents(value)
        case .perMinute:
            guard let value = parsedRate(text), (pricing.minPerMinute...pricing.maxPerMinute).contains(value) else { return }
            draftPerMinute = roundToCents(value)
        }
    }

    private func stepRate(field: RateField, delta: Double) {
        switch field {
        case .perMile:
            let next = roundToCents(min(max(currentPerMile + delta, pricing.minPerMile), pricing.maxPerMile))
            draftPerMile = next
            perMileText = rateText(next)
        case .perMinute:
            let next = roundToCents(min(max(currentPerMinute + delta, pricing.minPerMinute), pricing.maxPerMinute))
            draftPerMinute = next
            perMinuteText = rateText(next)
        }
    }

    private func setRate(field: RateField, value: Double) {
        switch field {
        case .perMile:
            let next = roundToCents(min(max(value, pricing.minPerMile), pricing.maxPerMile))
            draftPerMile = next
            perMileText = rateText(next)
        case .perMinute:
            let next = roundToCents(min(max(value, pricing.minPerMinute), pricing.maxPerMinute))
            draftPerMinute = next
            perMinuteText = rateText(next)
        }
    }

    private func resetDrafts() {
        draftPerMile = nil
        draftPerMinute = nil
        perMileText = rateText(rate.perMile)
        perMinuteText = rateText(rate.perMinute)
    }

    private func saveRateChanges() {
        guard canSaveRate else { return }
        onSaveRate(currentPerMile, currentPerMinute)
        resetDrafts()
    }

    private func isValidRateText(_ text: String, bounds: ClosedRange<Double>) -> Bool {
        guard let value = parsedRate(text) else { return false }
        return bounds.contains(value)
    }

    private func parsedRate(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let pattern = #"^\d+\.\d{2}$"#
        guard trimmed.range(of: pattern, options: .regularExpression) != nil else { return nil }
        return Double(trimmed)
    }

    private func rateText(_ value: Double) -> String {
        String(format: "%.2f", value)
    }

    private func suggestedRate(min: Double, max: Double) -> Double {
        roundToCents(min + ((max - min) * 0.30))
    }

    private func roundToCents(_ value: Double) -> Double {
        (value * 100).rounded() / 100
    }

    private func cardBackground(cornerRadius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Color(.systemBackground))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.black.opacity(0.06), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.07), radius: 16, y: 8)
    }

    private var rateStatusText: String {
        if hasDraftChanges { return "Unsaved" }
        return hasSavedRate ? "Saved" : "Not saved"
    }

    private var rateStatusIcon: String {
        if hasDraftChanges { return "exclamationmark.circle.fill" }
        return hasSavedRate ? "checkmark.circle.fill" : "dollarsign.circle"
    }

    private var rateStatusColor: Color {
        if hasDraftChanges { return .orange }
        return hasSavedRate ? .green : .secondary
    }

    private var lockedMessage: String {
        switch rideType {
        case "Rydr Eco", "Rydr XL": return "Vehicle Requirement Needed"
        case "Rydr Prestine": return "Driver Rating Required"
        case "Rydr Executive": return "Application Required"
        default: return "Pending Qualification"
        }
    }

    private var requirements: [String] {
        switch rideType {
        case "Rydr Eco":
            return ["Electric vehicle qualification", "Approved Rydr driver account"]
        case "Rydr XL":
            return ["Large SUV or qualifying high-capacity vehicle"]
        case "Rydr Prestine":
            return ["Vehicle less than 7 years old", "Clean interior and exterior", "No visible damage", "Driver rating 4.8+"]
        case "Rydr Executive":
            return ["Luxury sedan or SUV", "Vehicle less than 5 years old", "Leather interior", "Driver rating 4.9+", "Executive approval required"]
        default:
            return ["Approved standard vehicle", "Good standing on the platform"]
        }
    }

    private var icon: String {
        switch rideType {
        case "Rydr Eco": return "leaf.fill"
        case "Rydr XL": return "suv.side.fill"
        case "Rydr Prestine": return "sparkles"
        case "Rydr Executive": return "briefcase.fill"
        default: return "car.fill"
        }
    }
}

struct EarningsHubView: View {
    @ObservedObject var vm: DriverDashboardVM

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    earningsHero

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        InsightMetricCard(title: "Today", value: currency(vm.earningsSummary.todayEarnings), icon: "sun.max.fill")
                        InsightMetricCard(title: "This Week", value: currency(vm.earningsSummary.weekEarnings), icon: "calendar")
                        InsightMetricCard(title: "This Month", value: currency(vm.earningsSummary.monthEarnings), icon: "chart.bar.fill")
                        InsightMetricCard(title: "Recent Trips", value: "\(vm.earningsSummary.recentTrips.count)", icon: "car.fill")
                    }

                    dashboardSection("Performance") {
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                            InsightMetricCard(title: "Acceptance Rate", value: percent(vm.earningsSummary.acceptanceRate), icon: "checkmark.seal.fill")
                            InsightMetricCard(title: "Completion Rate", value: percent(vm.earningsSummary.completionRate), icon: "flag.checkered")
                        }
                    }

                    if vm.isLoadingEarningsSummary {
                        HStack {
                            ProgressView()
                            Text("Updating earnings…")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    dashboardSection("Recent Trips") {
                        if vm.earningsSummary.recentTrips.isEmpty {
                            Text(vm.isLoadingEarningsSummary ? "Loading recent trips…" : "No completed trips yet.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(vm.earningsSummary.recentTrips) { trip in
                                recentTripRow(trip)
                            }
                        }
                    }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Earnings Hub")
            .task {
                vm.refreshEarningsSummary()
            }
            .refreshable {
                vm.refreshEarningsSummary()
            }
        }
    }

    private var earningsHero: some View {
        ZStack(alignment: .trailing) {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(Styles.rydrGradient)

            Image(systemName: "dollarsign.circle.fill")
                .font(.system(size: 104, weight: .black))
                .foregroundStyle(Color.white.opacity(0.18))
                .offset(x: 18, y: 16)

            VStack(alignment: .leading, spacing: 8) {
                Text("Earnings Hub")
                    .font(.title.weight(.black))
                    .foregroundStyle(.white)
                Text("Track money already earned from completed rides.")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.9))
                Text(currency(vm.earningsSummary.todayEarnings))
                    .font(.system(size: 44, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .monospacedDigit()
                Text("earned today")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white.opacity(0.82))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(22)
        }
        .frame(minHeight: 190)
        .shadow(color: Color.red.opacity(0.22), radius: 18, y: 10)
    }

    private func recentTripRow(_ trip: DriverRecentTrip) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.title3.weight(.bold))
                .foregroundStyle(.green)
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 5) {
                Text("\(trip.pickup) → \(trip.dropoff)")
                    .font(.subheadline.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                if let completedAt = trip.completedAt {
                    Text(completedAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 8)

            Text(currency(trip.fare))
                .font(.headline.monospacedDigit().weight(.bold))
                .foregroundStyle(.green)
        }
        .padding(.vertical, 8)
    }

    private func percent(_ value: Double?) -> String {
        guard let value else { return "—" }
        return "\(Int((value * 100).rounded()))%"
    }

    private func dashboardSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
            content()
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 20).fill(Color(.secondarySystemBackground)))
    }

    private func currency(_ value: Decimal) -> String {
        currencyFormatter.string(from: value as NSDecimalNumber) ?? "$0.00"
    }
}

struct InsightMetricCard: View {
    let title: String
    let value: String
    let icon: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(Styles.rydrGradient)
            Text(value)
                .font(.title3.monospacedDigit().weight(.bold))
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 18).fill(Color(.secondarySystemBackground)))
    }
}

private enum DriverCommunityTab: String, CaseIterable, Identifiable {
    case hotspots = "Hotspots"
    case events = "Events"
    case stadiums = "Stadiums"
    case theaters = "Theaters"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .hotspots: return "flame.fill"
        case .events: return "calendar.badge.clock"
        case .stadiums: return "sportscourt.fill"
        case .theaters: return "theatermasks.fill"
        }
    }
}

private enum DriverCommunityDemandLevel: Int, Comparable {
    case low
    case moderate
    case high
    case veryHigh

    static func < (lhs: DriverCommunityDemandLevel, rhs: DriverCommunityDemandLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var title: String {
        switch self {
        case .low: return "Low"
        case .moderate: return "Moderate"
        case .high: return "High"
        case .veryHigh: return "Very high"
        }
    }

    var color: Color {
        switch self {
        case .low: return Color(red: 0.58, green: 0.59, blue: 0.68)
        case .moderate: return Color(red: 1.0, green: 0.73, blue: 0.25)
        case .high: return Color(red: 1.0, green: 0.49, blue: 0.22)
        case .veryHigh: return Color(red: 1.0, green: 0.16, blue: 0.22)
        }
    }
}

private struct DriverCommunityEvent: Identifiable, Decodable {
    let id: String
    let title: String
    let category: String
    let genre: String?
    let dateText: String?
    let localDate: String?
    let localTime: String?
    let venueName: String
    let city: String
    let state: String
    let address: String?
    let latitude: Double?
    let longitude: Double?
    let imageURL: URL?
    let ticketURL: URL?

    var coordinate: CLLocationCoordinate2D? {
        guard let latitude, let longitude else { return nil }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var parsedDate: Date? {
        guard let localDate else { return nil }
        return Self.dateFormatter.date(from: localDate)
    }

    var displayDate: String {
        guard let date = parsedDate else { return dateText ?? "Date TBA" }
        return Self.displayDateFormatter.string(from: date).uppercased()
    }

    var displayTime: String {
        guard let localTime else { return "Time TBA" }
        return String(localTime.prefix(5))
    }

    var venueLine: String {
        "\(venueName) • \(city), \(state)"
    }

    var isAirportRelated: Bool {
        let text = [title, venueName, address, category, genre]
            .compactMap { $0 }
            .joined(separator: " ")
            .lowercased()
        return text.contains("airport")
            || text.contains("hartsfield")
            || text.contains("atlanta int")
            || text.contains("atl ")
    }

    var isStadiumOrArena: Bool {
        let text = [venueName, category, genre]
            .compactMap { $0 }
            .joined(separator: " ")
            .lowercased()
        return text.contains("stadium")
            || text.contains("arena")
            || text.contains("park")
            || text.contains("field")
            || text.contains("sports")
    }

    var isTheater: Bool {
        let text = [venueName, category, genre]
            .compactMap { $0 }
            .joined(separator: " ")
            .lowercased()
        return text.contains("theater")
            || text.contains("theatre")
            || text.contains("arts")
            || text.contains("comedy")
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static let displayDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE MMM d"
        return formatter
    }()
}

private struct DriverCommunityEventsResponse: Decodable {
    let events: [DriverCommunityEvent]
}

private struct DriverCommunityRideRequest {
    let id: String
    let coordinate: CLLocationCoordinate2D?
    let createdAt: Date?
    let status: String

    init(document: QueryDocumentSnapshot) {
        let data = document.data()
        id = document.documentID
        coordinate = Self.coordinate(from: data["pickupCoordinate"] ?? data["pickupLocation"] ?? data["pickupGeoPoint"])
        createdAt = (data["createdAt"] as? Timestamp)?.dateValue()
        status = data["status"] as? String ?? ""
    }

    private static func coordinate(from value: Any?) -> CLLocationCoordinate2D? {
        if let point = value as? GeoPoint {
            return CLLocationCoordinate2D(latitude: point.latitude, longitude: point.longitude)
        }
        guard let data = value as? [String: Any] else { return nil }
        let lat = data["lat"] as? Double ?? data["latitude"] as? Double ?? (data["lat"] as? NSNumber)?.doubleValue
        let lng = data["lng"] as? Double ?? data["longitude"] as? Double ?? (data["lng"] as? NSNumber)?.doubleValue
        guard let lat, let lng else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lng)
    }
}

private struct DriverCommunitySupplyDriver {
    let id: String
    let coordinate: CLLocationCoordinate2D?

    init(document: QueryDocumentSnapshot) {
        let data = document.data()
        id = document.documentID
        coordinate = Self.coordinate(from: data["geoPoint"] ?? data["location"] ?? data["approximateLocation"])
    }

    private static func coordinate(from value: Any?) -> CLLocationCoordinate2D? {
        if let point = value as? GeoPoint {
            return CLLocationCoordinate2D(latitude: point.latitude, longitude: point.longitude)
        }
        guard let data = value as? [String: Any] else { return nil }
        let lat = data["lat"] as? Double ?? data["latitude"] as? Double ?? (data["lat"] as? NSNumber)?.doubleValue
        let lng = data["lng"] as? Double ?? data["longitude"] as? Double ?? (data["lng"] as? NSNumber)?.doubleValue
        guard let lat, let lng else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lng)
    }
}

private struct DriverCommunityHotspot: Identifiable {
    let event: DriverCommunityEvent
    let requestCount: Int
    let availableDrivers: Int
    let level: DriverCommunityDemandLevel

    var id: String { event.id }
    var coordinate: CLLocationCoordinate2D { event.coordinate ?? DriverMapDefaults.pilotCoordinate }
    var requestRatePerMinute: Double { Double(requestCount) / 2.0 }
    var supplyRatio: Double { Double(requestCount) / Double(max(availableDrivers, 1)) }
}

@MainActor
private final class DriverCommunityHubVM: ObservableObject {
    @Published var events: [DriverCommunityEvent] = []
    @Published var rideRequests: [DriverCommunityRideRequest] = []
    @Published var availableDrivers: [DriverCommunitySupplyDriver] = []
    @Published var isLoadingEvents = false
    @Published var errorMessage: String?

    private let db = Firestore.firestore()
    private var driverListener: ListenerRegistration?

    var hotspots: [DriverCommunityHotspot] {
        events.compactMap { event in
            guard !event.isAirportRelated, let eventCoordinate = event.coordinate else { return nil }
            let requests = rideRequests.filter { request in
                guard let coordinate = request.coordinate,
                      !Self.isAirportCoordinate(coordinate),
                      Self.isLiveDemandStatus(request.status) else { return false }
                return Self.distanceMiles(from: coordinate, to: eventCoordinate) <= 1.35
            }
            let drivers = availableDrivers.filter { driver in
                guard let coordinate = driver.coordinate else { return false }
                return Self.distanceMiles(from: coordinate, to: eventCoordinate) <= 3.0
            }
            return DriverCommunityHotspot(
                event: event,
                requestCount: requests.count,
                availableDrivers: drivers.count,
                level: Self.demandLevel(requests: requests.count, drivers: drivers.count)
            )
        }
        .sorted {
            if $0.level != $1.level { return $0.level > $1.level }
            if $0.requestCount != $1.requestCount { return $0.requestCount > $1.requestCount }
            return ($0.event.parsedDate ?? .distantFuture) < ($1.event.parsedDate ?? .distantFuture)
        }
    }

    var currentLevel: DriverCommunityDemandLevel {
        hotspots.map(\.level).max() ?? .low
    }

    var activeRequestCount: Int {
        rideRequests.filter { Self.isLiveDemandStatus($0.status) }.count
    }

    func start() {
        loadEvents()
        startDemandListeners()
    }

    func stop() {
        driverListener?.remove()
        driverListener = nil
    }

    func refresh() {
        loadEvents()
    }

    private func loadEvents() {
        isLoadingEvents = true
        errorMessage = nil
        Task {
            do {
                let events = try await Self.fetchEvents()
                    .filter { !$0.isAirportRelated }
                self.events = events
                self.isLoadingEvents = false
            } catch {
                self.errorMessage = error.localizedDescription
                self.isLoadingEvents = false
            }
        }
    }

    private func startDemandListeners() {
        driverListener?.remove()
        driverListener = db.collection("driver_status")
            .whereField("isOnline", isEqualTo: true)
            .limit(to: 150)
            .addSnapshotListener { [weak self] snapshot, error in
                Task { @MainActor in
                    guard let self else { return }
                    if let error {
                        self.errorMessage = error.localizedDescription
                        return
                    }
                    self.availableDrivers = (snapshot?.documents ?? [])
                        .map(DriverCommunitySupplyDriver.init(document:))
                }
            }
    }

    private static func fetchEvents() async throws -> [DriverCommunityEvent] {
        let backendBaseURL = try resolvedBackendBaseURL()
        var components = URLComponents(url: backendBaseURL.appendingPathComponent("events"), resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "category", value: "featured"),
            URLQueryItem(name: "city", value: "Atlanta"),
            URLQueryItem(name: "stateCode", value: "GA"),
            URLQueryItem(name: "size", value: "30")
        ]
        guard let url = components?.url else { throw URLError(.badURL) }

        var request = URLRequest(url: url)
        request.timeoutInterval = 18
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(DriverCommunityEventsResponse.self, from: data).events
    }

    private static func resolvedBackendBaseURL() throws -> URL {
        #if DEBUG
        if let override = UserDefaults.standard.string(forKey: "communityBackendBaseURL"),
           let url = URL(string: override),
           !override.isEmpty {
            return url
        }
        #endif

        if let value = Bundle.main.object(forInfoDictionaryKey: "RYDR_BACKEND_BASE_URL") as? String,
           let url = URL(string: value),
           !value.isEmpty {
            return url
        }

        throw DriverCommunityBackendError.missingConfiguration
    }

    private static func demandLevel(requests: Int, drivers: Int) -> DriverCommunityDemandLevel {
        let ratio = Double(requests) / Double(max(drivers, 1))
        if requests >= 20 || ratio >= 4.0 { return .veryHigh }
        if requests >= 10 || ratio >= 2.0 { return .high }
        if requests >= 3 || ratio >= 1.0 { return .moderate }
        return .low
    }

    private static func isLiveDemandStatus(_ status: String) -> Bool {
        let normalized = status.lowercased()
        return normalized.isEmpty || ["pending", "open", "searching", "requested"].contains(normalized)
    }

    private static func distanceMiles(from lhs: CLLocationCoordinate2D, to rhs: CLLocationCoordinate2D) -> Double {
        CLLocation(latitude: lhs.latitude, longitude: lhs.longitude)
            .distance(from: CLLocation(latitude: rhs.latitude, longitude: rhs.longitude)) / 1609.344
    }

    private static func isAirportCoordinate(_ coordinate: CLLocationCoordinate2D) -> Bool {
        let airport = CLLocationCoordinate2D(latitude: 33.6407, longitude: -84.4277)
        return distanceMiles(from: coordinate, to: airport) <= 2.0
    }
}

private enum DriverCommunityBackendError: LocalizedError {
    case missingConfiguration

    var errorDescription: String? {
        switch self {
        case .missingConfiguration:
            return "Rydr Community is missing its backend configuration."
        }
    }
}

private struct DriverCommunityHubView: View {
    @StateObject private var vm = DriverCommunityHubVM()
    @State private var selectedTab: DriverCommunityTab = .hotspots
    @State private var mapPosition: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: DriverMapDefaults.pilotCoordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.34, longitudeDelta: 0.42)
        )
    )

    private var visibleHotspots: [DriverCommunityHotspot] {
        switch selectedTab {
        case .hotspots:
            return vm.hotspots
        case .events:
            return vm.hotspots
        case .stadiums:
            return vm.hotspots.filter { $0.event.isStadiumOrArena }
        case .theaters:
            return vm.hotspots.filter { $0.event.isTheater }
        }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 20) {
                communityHero
                tabBar
                demandSummaryCard
                eventHotspotMap
                upcomingEventsSection
                proTipCard
            }
            .padding(.horizontal, 18)
            .padding(.top, 16)
            .padding(.bottom, 30)
        }
        .background(
            LinearGradient(
                colors: [Color(.systemBackground), Color(red: 1.0, green: 0.965, blue: 0.97)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        )
        .navigationTitle("Community")
        .navigationBarTitleDisplayMode(.inline)
        .task { vm.start() }
        .onDisappear { vm.stop() }
        .refreshable { vm.refresh() }
        .alert("Community", isPresented: Binding(
            get: { vm.errorMessage != nil },
            set: { if !$0 { vm.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(vm.errorMessage ?? "")
        }
    }

    private var communityHero: some View {
        ZStack(alignment: .trailing) {
            DriverCommunityMapPattern()
                .frame(width: 190, height: 150)
                .opacity(0.65)
                .accessibilityHidden(true)

            Image(systemName: "mappin.circle.fill")
                .font(.system(size: 92, weight: .black))
                .foregroundStyle(Styles.rydrGradient)
                .shadow(color: Color.red.opacity(0.22), radius: 18, y: 10)
                .offset(x: -16, y: 2)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 10) {
                Label("Atlanta, GA", systemImage: "mappin.circle.fill")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(Styles.rydrGradient)

                Text("Go where the rides are")
                    .font(.system(size: 34, weight: .black, design: .rounded))
                    .foregroundStyle(Styles.rydrGradient)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Real-time event hotspots and venue demand to help you position for more rides in Metro Atlanta.")
                    .font(.body.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineSpacing(4)
                    .frame(maxWidth: 285, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.trailing, 96)
        }
        .frame(minHeight: 178)
    }

    private var tabBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(DriverCommunityTab.allCases) { tab in
                    Button {
                        withAnimation(.snappy(duration: 0.22)) {
                            selectedTab = tab
                        }
                    } label: {
                        Label(tab.rawValue, systemImage: tab.icon)
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(selectedTab == tab ? Color.white : Color.primary)
                            .padding(.horizontal, 16)
                            .frame(height: 48)
                            .background(
                                Capsule()
                                    .fill(selectedTab == tab ? AnyShapeStyle(Styles.rydrGradient) : AnyShapeStyle(Color(.systemBackground)))
                                    .shadow(color: selectedTab == tab ? Color.red.opacity(0.22) : Color.black.opacity(0.04), radius: 12, y: 6)
                            )
                            .overlay(
                                Capsule()
                                    .stroke(selectedTab == tab ? Color.clear : Color.black.opacity(0.08), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 2)
        }
    }

    private var demandSummaryCard: some View {
        HStack(spacing: 18) {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.22))
                    .frame(width: 62, height: 62)
                Image(systemName: "flame.fill")
                    .font(.title.weight(.black))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Right now")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.82))
                Text("\(vm.currentLevel.title) demand")
                    .font(.title2.weight(.black))
                    .foregroundStyle(.white)
                Text("\(vm.activeRequestCount) requests in the last 2 minutes")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.white.opacity(0.88))
            }

            Spacer()

            VStack(alignment: .leading, spacing: 8) {
                demandMeterRow("Now", level: vm.currentLevel)
                demandMeterRow("Next", level: projectedLevel)
                demandMeterRow("Later", level: visibleHotspots.isEmpty ? .low : .moderate)
            }
            .frame(width: 126)
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Styles.rydrGradient)
        )
        .shadow(color: Color.red.opacity(0.22), radius: 18, y: 10)
    }

    private var projectedLevel: DriverCommunityDemandLevel {
        let upcomingSoon = visibleHotspots.contains { hotspot in
            guard let date = hotspot.event.parsedDate else { return false }
            return date.timeIntervalSince(Date()) < 36 * 60 * 60
        }
        if vm.currentLevel >= .high { return vm.currentLevel }
        return upcomingSoon ? .moderate : .low
    }

    private func demandMeterRow(_ title: String, level: DriverCommunityDemandLevel) -> some View {
        HStack(spacing: 7) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.82))
                .frame(width: 34, alignment: .leading)
            HStack(spacing: 3) {
                ForEach(0..<4, id: \.self) { index in
                    Capsule()
                        .fill(index <= level.rawValue ? Color.white.opacity(0.82) : Color.white.opacity(0.22))
                        .frame(width: 16, height: 6)
                }
            }
        }
    }

    private var eventHotspotMap: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                Map(position: $mapPosition) {
                    ForEach(visibleHotspots) { hotspot in
                        Annotation(hotspot.event.venueName, coordinate: hotspot.coordinate) {
                            DriverEventHotspotAnnotation(hotspot: hotspot)
                        }
                    }
                }
                .mapStyle(.standard(elevation: .flat))
                .frame(height: 360)
                .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .fill(Color.black.opacity(0.18))
                        .allowsHitTesting(false)
                )

                HStack {
                    Label("Live event demand", systemImage: "circle.fill")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .frame(height: 44)
                        .background(.black.opacity(0.62), in: Capsule())
                    Spacer()
                    Button {
                        focusMap()
                    } label: {
                        Label("Fit venues", systemImage: "list.bullet")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 14)
                            .frame(height: 44)
                            .background(.black.opacity(0.62), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
                .padding(14)
            }

            DriverCommunityLegend()
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
                .background(Color(.secondarySystemBackground))
        }
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .shadow(color: Color.black.opacity(0.10), radius: 18, y: 10)
        .onChange(of: visibleHotspots.map(\.id)) { _, _ in
            focusMap()
        }
    }

    private func focusMap() {
        let coordinates = visibleHotspots.compactMap { $0.event.coordinate }
        guard !coordinates.isEmpty else { return }
        let minLat = coordinates.map(\.latitude).min() ?? DriverMapDefaults.pilotCoordinate.latitude
        let maxLat = coordinates.map(\.latitude).max() ?? DriverMapDefaults.pilotCoordinate.latitude
        let minLng = coordinates.map(\.longitude).min() ?? DriverMapDefaults.pilotCoordinate.longitude
        let maxLng = coordinates.map(\.longitude).max() ?? DriverMapDefaults.pilotCoordinate.longitude
        let center = CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLng + maxLng) / 2)
        let span = MKCoordinateSpan(
            latitudeDelta: max(0.14, (maxLat - minLat) * 1.8),
            longitudeDelta: max(0.18, (maxLng - minLng) * 1.8)
        )
        mapPosition = .region(MKCoordinateRegion(center: center, span: span))
    }

    private var upcomingEventsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Upcoming events near you")
                    .font(.title3.weight(.black))
                Spacer()
                if vm.isLoadingEvents {
                    ProgressView()
                }
            }

            if visibleHotspots.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Label("No eligible event hotspots yet", systemImage: "calendar.badge.exclamationmark")
                        .font(.headline.weight(.bold))
                    Text("Events from airports are hidden. Stadiums, arenas, theaters, and other eligible venues will appear when Ticketmaster has upcoming Atlanta events.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            } else {
                ForEach(visibleHotspots.prefix(4)) { hotspot in
                    DriverCommunityEventCard(hotspot: hotspot)
                }
            }
        }
    }

    private var proTipCard: some View {
        HStack(spacing: 14) {
            Image(systemName: "sparkles")
                .font(.title2.weight(.black))
                .foregroundStyle(Styles.rydrGradient)
                .frame(width: 58, height: 58)
                .background(Color.red.opacity(0.09), in: Circle())
            VStack(alignment: .leading, spacing: 5) {
                Text("Pro tip")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Styles.rydrGradient)
                Text("Arrive 60-90 min early and stay after events to catch the most ride requests.")
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(18)
        .background(
            LinearGradient(
                colors: [Color.red.opacity(0.10), Color(.systemBackground)],
                startPoint: .leading,
                endPoint: .trailing
            ),
            in: RoundedRectangle(cornerRadius: 24, style: .continuous)
        )
    }
}

private struct DriverEventHotspotAnnotation: View {
    let hotspot: DriverCommunityHotspot

    var body: some View {
        VStack(spacing: 8) {
            VStack(spacing: 4) {
                Text(hotspot.event.venueName)
                    .font(.caption.weight(.black))
                    .lineLimit(1)
                Text(hotspot.level.title)
                    .font(.caption2.weight(.semibold))
                HStack(spacing: 3) {
                    ForEach(0..<4, id: \.self) { index in
                        Circle()
                            .fill(index <= hotspot.level.rawValue ? hotspot.level.color : Color.white.opacity(0.42))
                            .frame(width: 6, height: 6)
                    }
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(width: 132)
            .background(.black.opacity(0.48), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(hotspot.level.color.opacity(0.72), lineWidth: 1)
            )

            ZStack {
                Circle()
                    .fill(hotspot.level.color.opacity(0.18))
                    .frame(width: glowSize, height: glowSize)
                    .blur(radius: 8)
                Circle()
                    .stroke(Styles.rydrGradient, lineWidth: 3)
                    .frame(width: 34, height: 34)
                    .shadow(color: hotspot.level.color.opacity(0.6), radius: 16)
                Image(systemName: hotspot.event.isTheater ? "theatermasks.fill" : "building.columns.fill")
                    .font(.caption.weight(.black))
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(Styles.rydrGradient, in: Circle())
            }
        }
    }

    private var glowSize: CGFloat {
        switch hotspot.level {
        case .low: return 48
        case .moderate: return 64
        case .high: return 82
        case .veryHigh: return 102
        }
    }
}

private struct DriverCommunityLegend: View {
    var body: some View {
        HStack(spacing: 14) {
            ForEach([DriverCommunityDemandLevel.veryHigh, .high, .moderate, .low], id: \.rawValue) { level in
                HStack(spacing: 6) {
                    Circle()
                        .fill(level.color)
                        .frame(width: 10, height: 10)
                    Text(level.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Image(systemName: "info.circle")
                .font(.callout.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }
}

private struct DriverCommunityEventCard: View {
    let hotspot: DriverCommunityHotspot

    var body: some View {
        HStack(spacing: 14) {
            VStack(spacing: 4) {
                Text(hotspot.event.displayDate)
                    .font(.caption.weight(.black))
                    .multilineTextAlignment(.center)
                Text(hotspot.event.displayTime)
                    .font(.caption2.weight(.bold))
                    .multilineTextAlignment(.center)
            }
            .foregroundStyle(.white)
            .frame(width: 76, height: 86)
            .background(Styles.rydrGradient, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

            VStack(alignment: .leading, spacing: 8) {
                Text(hotspot.event.title)
                    .font(.headline.weight(.black))
                    .lineLimit(2)
                Text(hotspot.event.venueLine)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    Label(hotspot.level.title, systemImage: "flame.fill")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(hotspot.level.color)
                        .padding(.horizontal, 10)
                        .frame(height: 28)
                        .background(hotspot.level.color.opacity(0.12), in: Capsule())
                    Label("\(hotspot.requestCount) recent", systemImage: "clock")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.black.opacity(0.06), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.04), radius: 10, y: 5)
    }
}

private struct DriverCommunityMapPattern: View {
    var body: some View {
        Canvas { context, size in
            let stroke = StrokeStyle(lineWidth: 1.2, lineCap: .round)
            for index in 0..<7 {
                var path = Path()
                let y = CGFloat(index) * size.height / 6
                path.move(to: CGPoint(x: 0, y: y))
                path.addCurve(
                    to: CGPoint(x: size.width, y: y + CGFloat(index % 2 == 0 ? 24 : -18)),
                    control1: CGPoint(x: size.width * 0.32, y: y - 26),
                    control2: CGPoint(x: size.width * 0.66, y: y + 30)
                )
                context.stroke(path, with: .color(Color.red.opacity(0.10)), style: stroke)
            }
            for index in 0..<5 {
                var path = Path()
                let x = CGFloat(index) * size.width / 4
                path.move(to: CGPoint(x: x, y: 0))
                path.addCurve(
                    to: CGPoint(x: x + CGFloat(index % 2 == 0 ? 20 : -22), y: size.height),
                    control1: CGPoint(x: x + 22, y: size.height * 0.3),
                    control2: CGPoint(x: x - 28, y: size.height * 0.68)
                )
                context.stroke(path, with: .color(Color.red.opacity(0.08)), style: stroke)
            }
        }
    }
}

struct DriverNotificationsView: View {
    @ObservedObject var vm: DriverDashboardVM

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 14) {
                headerCard

                if let message = vm.notificationErrorMessage {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.orange)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(Color.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }

                if vm.driverNotifications.isEmpty {
                    emptyNotifications
                } else {
                    VStack(spacing: 10) {
                        ForEach(vm.driverNotifications) { notification in
                            DriverNotificationRow(notification: notification) {
                                vm.markNotificationRead(notification)
                            } onDismiss: {
                                vm.dismissNotification(notification)
                            }
                        }
                    }
                }
            }
            .padding(16)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Mark Read") {
                    vm.markAllNotificationsRead()
                }
                .font(.subheadline.weight(.bold))
                .disabled(vm.unreadNotificationCount == 0)
            }
        }
    }

    private var headerCard: some View {
        HStack(spacing: 14) {
            Image(systemName: "bell.badge.fill")
                .font(.title2.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 48, height: 48)
                .background(Styles.rydrGradient, in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(vm.unreadNotificationCount == 0 ? "All caught up" : "\(vm.unreadNotificationCount) unread")
                    .font(.headline.weight(.bold))
                Text("Ride requests, demand alerts, safety updates, and Mission Control notices appear here.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(16)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.black.opacity(0.06), lineWidth: 1)
        )
    }

    private var emptyNotifications: some View {
        VStack(spacing: 10) {
            Image(systemName: "bell.slash.fill")
                .font(.title.weight(.bold))
                .foregroundStyle(.secondary)
            Text("No notifications yet")
                .font(.headline.weight(.bold))
            Text("Live driver alerts will appear here as they are received.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 44)
        .padding(.horizontal, 16)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

private struct DriverNotificationRow: View {
    let notification: DriverNotificationItem
    let onRead: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: notification.icon)
                .font(.headline.weight(.bold))
                .foregroundStyle(iconColor)
                .frame(width: 40, height: 40)
                .background(Circle().fill(iconColor.opacity(0.12)))

            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(notification.title)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.primary)
                    if !notification.isRead {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 7, height: 7)
                    }
                    Spacer()
                    Text(relativeTime)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                Text(notification.message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.caption.weight(.heavy))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .background(Color(.secondarySystemGroupedBackground), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss notification")
        }
        .padding(14)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(notification.isRead ? Color.black.opacity(0.05) : Color.red.opacity(0.24), lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onRead)
    }

    private var iconColor: Color {
        switch notification.priority {
        case .urgent: return .red
        case .high: return .orange
        case .normal: return .secondary
        }
    }

    private var relativeTime: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: notification.createdAt, relativeTo: Date())
    }
}

struct DriverHelpSupportView: View {
    @State private var searchText = ""

    private let discordURL = URL(string: "https://discord.gg/kfUz52849")!

    private var filteredArticles: [DriverSupportArticle] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return DriverSupportArticle.library }
        return DriverSupportArticle.library.filter { article in
            article.title.lowercased().contains(query) ||
                article.category.lowercased().contains(query) ||
                article.summary.lowercased().contains(query) ||
                article.steps.joined(separator: " ").lowercased().contains(query)
        }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 14) {
                supportHero
                searchField
                discordCard

                VStack(spacing: 10) {
                    ForEach(filteredArticles) { article in
                        DriverSupportArticleCard(article: article)
                    }
                }
            }
            .padding(16)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Help & Support")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var supportHero: some View {
        HStack(spacing: 14) {
            Image(systemName: "questionmark.bubble.fill")
                .font(.title2.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 50, height: 50)
                .background(Styles.rydrGradient, in: Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text("Driver knowledge base")
                    .font(.headline.weight(.bold))
                Text("Quick answers for beta drivers, onboarding, ride flow, earnings, safety, and app troubleshooting.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(16)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search articles", text: $searchText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(13)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var discordCard: some View {
        Link(destination: discordURL) {
            HStack(spacing: 12) {
                Image(systemName: "person.2.wave.2.fill")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 42, height: 42)
                    .background(Color.indigo, in: Circle())

                VStack(alignment: .leading, spacing: 3) {
                    Text("Live beta support")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.primary)
                    Text("Join the Rydr Live Beta Discord for support during the beta.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Spacer()
                Image(systemName: "arrow.up.right.square.fill")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(Color.indigo)
            }
            .padding(14)
            .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.indigo.opacity(0.20), lineWidth: 1)
            )
        }
    }
}

private struct DriverSupportArticleCard: View {
    let article: DriverSupportArticle

    var body: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 9) {
                Text(article.summary)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                ForEach(article.steps, id: \.self) { step in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Color.green)
                            .padding(.top, 2)
                        Text(step)
                            .font(.footnote)
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(.top, 8)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: article.icon)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(Styles.rydrGradient)
                    .frame(width: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text(article.title)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.primary)
                    Text(article.category)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(14)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.black.opacity(0.05), lineWidth: 1)
        )
    }
}

private struct DriverSupportArticle: Identifiable {
    let id: String
    let title: String
    let category: String
    let icon: String
    let summary: String
    let steps: [String]

    static let library: [DriverSupportArticle] = [
        DriverSupportArticle(
            id: "going-online",
            title: "Getting ready to go online",
            category: "Account readiness",
            icon: "power.circle.fill",
            summary: "A driver must be approved, have at least one active ride type, and save rates before receiving standard ride requests.",
            steps: [
                "Confirm Mission Control approval is complete.",
                "Open Vehicle & Rydr Hub and keep at least one eligible ride type active.",
                "Open the ride type rate card while offline, set rates in 0.00 format, and save changes."
            ]
        ),
        DriverSupportArticle(
            id: "ride-requests",
            title: "Handling ride requests",
            category: "Ride flow",
            icon: "car.fill",
            summary: "Assigned ride requests appear on the dashboard when you are online and match your active ride types and filters.",
            steps: [
                "Review pickup, drop-off, ride type, rider rating, and estimated fare before accepting.",
                "Accept only when you can safely reach pickup.",
                "Declined or missed requests may appear in earnings and performance analytics."
            ]
        ),
        DriverSupportArticle(
            id: "rates",
            title: "Editing per-mile and per-minute rates",
            category: "Rates",
            icon: "dollarsign.circle.fill",
            summary: "Rates can be changed only while offline so pricing does not change mid-dispatch.",
            steps: [
                "Open the ride type card from the dashboard or Vehicle & Rydr Hub.",
                "Use the edit field or plus/minus controls for each rate.",
                "Save the unsaved rate notification before going online."
            ]
        ),
        DriverSupportArticle(
            id: "safety-markers",
            title: "Safety markers and appeals",
            category: "Safety",
            icon: "shield.fill",
            summary: "Safety markers come from rider reports and Mission Control review. Some conduct concerns may place the account on hold.",
            steps: [
                "Open Safety to review active markers.",
                "Use Appeal when you have ride context or evidence Mission Control should review.",
                "Unprofessional conduct markers may temporarily suspend access until manual investigation is complete."
            ]
        ),
        DriverSupportArticle(
            id: "documents",
            title: "Document review status",
            category: "Onboarding",
            icon: "doc.text.fill",
            summary: "License, insurance, registration, identity, and beta background-check status affect approval readiness.",
            steps: [
                "Upload clear document images with all corners visible.",
                "Check Documents for missing or pending items.",
                "Mission Control handles beta approval and background-check bypass decisions."
            ]
        ),
        DriverSupportArticle(
            id: "notifications",
            title: "Notification types",
            category: "Alerts",
            icon: "bell.fill",
            summary: "The bell shows live ride, demand, missed request, safety, appeal, and Mission Control notices.",
            steps: [
                "Open Notifications from the bell or side menu.",
                "Unread alerts show a badge until opened or marked read.",
                "Device push alerts require notification permission and a saved Firebase token."
            ]
        ),
        DriverSupportArticle(
            id: "troubleshooting",
            title: "Common beta troubleshooting",
            category: "Beta support",
            icon: "wrench.and.screwdriver.fill",
            summary: "Most beta issues come from permissions, stale approval status, missing rates, or network state.",
            steps: [
                "Confirm location and notification permissions are enabled.",
                "Close and reopen the app after Mission Control changes approval status.",
                "Share screenshots and the time of the issue in the Rydr Live Beta Discord."
            ]
        )
    ]
}

struct DrawerDestinationView: View {
    let item: SideMenuItem
    @ObservedObject var vm: DriverDashboardVM

    var body: some View {
        NavigationStack {
            if item == .profile {
                DriverProfileView(dashboardVM: vm)
            } else if item == .vehicleRideTypes {
                VehicleRydrHubView(vm: vm)
            } else if item == .cashRydrHub {
                DriverCashRydrHubView()
            } else if item == .community {
                DriverCommunityHubView()
            } else if item == .walletPayouts {
                DriverWalletPayoutsView(vm: vm)
            } else if item == .documents {
                DriverDocumentsView(vm: vm)
            } else if item == .settings {
                DriverSettingsView(vm: vm)
            } else if item == .safety {
                DriverSafetyCenterView(vm: vm)
            } else if item == .notifications {
                DriverNotificationsView(vm: vm)
            } else if item == .helpSupport {
                DriverHelpSupportView()
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        Text(subtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        ForEach(rows, id: \.self) { row in
                            HStack {
                                Image(systemName: rowIcon)
                                    .foregroundStyle(Styles.rydrGradient)
                                    .frame(width: 26)
                                Text(row)
                                    .font(.body.weight(.medium))
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(14)
                            .background(RoundedRectangle(cornerRadius: 16).fill(Color(.secondarySystemBackground)))
                            .accessibilityElement(children: .combine)
                        }

                    }
                    .padding()
                }
                .navigationTitle(item.rawValue)
            }
        }
    }

    private var subtitle: String {
        switch item {
        case .profile: return "Manage your public driver profile and preferences."
        case .vehicleRideTypes: return "Manage your vehicle, Rydr Hub qualifications, and approved ride types."
        case .fareInsights: return "Track completed-ride earnings, recent trip totals, and performance health."
        case .walletPayouts: return "Manage payout methods, instant pay, and payout history."
        case .cashRydrHub: return "Review open Cash Hub rider posts and manage accepted cash rides."
        case .documents: return "Keep required driver documents current."
        case .community: return "Find live event demand, venue hotspots, and upcoming Atlanta events."
        case .safety: return "Emergency contacts, incident reports, SafeRydr settings, and Safety Center."
        case .helpSupport: return "FAQs, support contact, and issue reporting."
        case .settings: return "Notifications, appearance, privacy, and location settings."
        case .notifications: return "Driver alerts, ride updates, document reminders, and payout messages."
        default: return "Driver tools and account management."
        }
    }

    private var rows: [String] {
        switch item {
        case .profile: return ["Profile Photo", "Bio", "Contact Information", "Driver Preferences"]
        case .vehicleRideTypes: return ["My Vehicle", "Ride Type Qualifications"] + DriverDashboardVM.availableRideTypes
        case .fareInsights: return ["Today", "This Week", "This Month", "Recent Trips"]
        case .walletPayouts: return ["Bank Account", "Debit Card", "Instant Pay", "Payout History"]
        case .cashRydrHub: return ["Open Requests", "Accepted Cash Rides", "Cash Hub Terms"]
        case .documents: return ["Driver License", "Insurance", "Registration", "Background Check Status"]
        case .community: return ["Live Hotspots", "Upcoming Events", "Venue Demand"]
        case .safety: return ["Emergency Contacts", "Incident Reports", "SafeRydr Settings", "Safety Center"]
        case .helpSupport: return ["FAQs", "Contact Support", "Report Issue"]
        case .settings: return ["Notifications", "Appearance", "Privacy", "Location Settings"]
        case .notifications: return ["Unread Ride Updates", "Document Reminders", "Payout Notices"]
        default: return []
        }
    }

    private var rowIcon: String { item.icon }

    private var accountDeletionCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Account deletion")
                .font(.headline.weight(.bold))
            Text("Submit a beta deletion request. This creates an audit record and lets support finish backend cleanup that requires admin access.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            if let message = vm.accountDeletionMessage {
                Text(message)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(message.localizedCaseInsensitiveContains("could not") ? .red : .secondary)
            }
            Button(role: .destructive) {
                vm.requestAccountDeletion()
            } label: {
                HStack {
                    if vm.isRequestingAccountDeletion {
                        ProgressView()
                    }
                    Text(vm.isRequestingAccountDeletion ? "Submitting..." : "Request Account Deletion")
                        .font(.subheadline.weight(.bold))
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(vm.isRequestingAccountDeletion)
            .accessibilityLabel("Request account deletion")
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(.secondarySystemBackground)))
    }
}
