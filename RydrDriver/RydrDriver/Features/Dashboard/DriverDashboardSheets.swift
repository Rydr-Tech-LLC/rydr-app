import SwiftUI

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

            Button {
                onSaveRate(currentPerMile, currentPerMinute)
                resetDrafts()
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
                Label("Custom rates must stay inside the listed range and use a $0.00 format.", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)
            }
        }
        .padding(20)
        .background(cardBackground(cornerRadius: 26))
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
                    Text("Current Rate")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    TextField(currencyText(value), text: text)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .font(.title2.weight(.heavy).monospacedDigit())
                        .foregroundStyle(isInputValid ? Color.primary : Color.red)
                        .frame(width: 116)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color(.systemBackground))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .stroke(isInputValid ? Color.clear : Color.red.opacity(0.6), lineWidth: 1)
                                )
                        )
                        .disabled(isOnline || !isEligible)
                        .onChange(of: text.wrappedValue) { _, newValue in
                            onTextChange(newValue)
                        }

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
                Text("Suggested \(currencyText(suggested))\(suffix)")
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
            perMileText = currencyText(next)
        case .perMinute:
            let next = roundToCents(min(max(currentPerMinute + delta, pricing.minPerMinute), pricing.maxPerMinute))
            draftPerMinute = next
            perMinuteText = currencyText(next)
        }
    }

    private func setRate(field: RateField, value: Double) {
        switch field {
        case .perMile:
            let next = roundToCents(min(max(value, pricing.minPerMile), pricing.maxPerMile))
            draftPerMile = next
            perMileText = currencyText(next)
        case .perMinute:
            let next = roundToCents(min(max(value, pricing.minPerMinute), pricing.maxPerMinute))
            draftPerMinute = next
            perMinuteText = currencyText(next)
        }
    }

    private func resetDrafts() {
        draftPerMile = nil
        draftPerMinute = nil
        perMileText = currencyText(rate.perMile)
        perMinuteText = currencyText(rate.perMinute)
    }

    private func isValidRateText(_ text: String, bounds: ClosedRange<Double>) -> Bool {
        guard let value = parsedRate(text) else { return false }
        return bounds.contains(value)
    }

    private func parsedRate(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let pattern = #"^\$?\d+\.\d{2}$"#
        guard trimmed.range(of: pattern, options: .regularExpression) != nil else { return nil }
        return Double(trimmed.replacingOccurrences(of: "$", with: ""))
    }

    private func currencyText(_ value: Double) -> String {
        "$\(String(format: "%.2f", value))"
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

struct FareInsightsView: View {
    @ObservedObject var vm: DriverDashboardVM

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        InsightMetricCard(title: "Today's Earnings", value: currency(vm.earningsToday), icon: "dollarsign.circle.fill")
                        InsightMetricCard(title: "Weekly Earnings", value: "$642.80", icon: "calendar")
                        InsightMetricCard(title: "Monthly Earnings", value: "$2,846.50", icon: "chart.bar.fill")
                        InsightMetricCard(title: "Acceptance Rate", value: "92%", icon: "checkmark.seal.fill")
                        InsightMetricCard(title: "Completion Rate", value: "97%", icon: "flag.checkered")
                        InsightMetricCard(title: "Demand Trend", value: "Rising", icon: "arrow.up.right")
                    }

                    dashboardSection("Ride Type Breakdown") {
                        ForEach(DriverDashboardVM.availableRideTypes, id: \.self) { rideType in
                            HStack {
                                Text(rideType)
                                Spacer()
                                Text(vm.selectedRideTypes.contains(rideType) ? "Active" : "Inactive")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(vm.selectedRideTypes.contains(rideType) ? .green : .secondary)
                            }
                            .font(.subheadline)
                        }
                    }

                    dashboardSection("Heatmap Performance") {
                        HStack {
                            Image(systemName: "flame.fill")
                                .foregroundStyle(Styles.rydrGradient)
                            Text("Airport corridor and downtown demand are strongest during evening commute windows.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }

                    dashboardSection("Current Rates") {
                        ForEach(vm.selectedRideTypes.sorted(by: tierSort), id: \.self) { rideType in
                            let rate = vm.rate(for: rideType)
                            HStack {
                                Text(rideType)
                                Spacer()
                                Text("$\(rate.perMile, specifier: "%.2f")/mi")
                                Text("$\(rate.perMinute, specifier: "%.2f")/min")
                            }
                            .font(.caption.monospacedDigit())
                        }
                    }

                    dashboardSection("Recommended Rate Adjustments") {
                        Text("Stay near the middle of each approved range during normal demand. Move toward the upper end only during sustained high-demand periods.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    dashboardSection("Recent Trips") {
                        ForEach(["Airport drop-off", "Downtown pickup", "Event district ride"], id: \.self) { trip in
                            HStack {
                                Text(trip)
                                Spacer()
                                Text("Completed")
                                    .font(.caption)
                                    .foregroundStyle(.green)
                            }
                            .font(.subheadline)
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Fare Insights")
        }
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

    private func tierSort(_ lhs: String, _ rhs: String) -> Bool {
        let ordered = DriverDashboardVM.availableRideTypes
        return (ordered.firstIndex(of: lhs) ?? ordered.endIndex) < (ordered.firstIndex(of: rhs) ?? ordered.endIndex)
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

struct DrawerDestinationView: View {
    let item: SideMenuItem
    @ObservedObject var vm: DriverDashboardVM

    var body: some View {
        NavigationStack {
            if item == .profile {
                DriverProfileView()
            } else if item == .community {
                DriverCashRydrHubView()
            } else if item == .walletPayouts {
                DriverWalletPayoutsView(vm: vm)
            } else if item == .settings {
                DriverSettingsView()
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
        case .vehicleRideTypes: return "Review vehicle information, qualifications, upgrade eligibility, and approved ride types."
        case .earnings: return "Track daily, weekly, monthly, and annual earnings with export-ready reports."
        case .walletPayouts: return "Manage payout methods, instant pay, and payout history."
        case .documents: return "Keep required driver documents current."
        case .rewards: return "Track milestones, referrals, promotions, and Rydr incentives."
        case .community: return "Access Cash Rydr Hub, local events, and community announcements."
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
        case .vehicleRideTypes: return ["Vehicle Information", "Ride Type Qualifications", "Upgrade Eligibility"] + DriverDashboardVM.availableRideTypes
        case .earnings: return ["Daily", "Weekly", "Monthly", "Annual", "Export Earnings Reports"]
        case .walletPayouts: return ["Bank Account", "Debit Card", "Instant Pay", "Payout History"]
        case .documents: return ["Driver License", "Insurance", "Registration", "Vehicle Inspection", "Background Check Status"]
        case .rewards: return ["Driver Milestones", "Referral Rewards", "Promotions", "Rydr Incentives"]
        case .community: return ["Cash Rydr Hub", "Local Events", "Community Announcements"]
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
