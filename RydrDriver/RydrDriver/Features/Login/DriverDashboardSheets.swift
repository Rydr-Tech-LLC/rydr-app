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

    private var canSaveRate: Bool {
        !isOnline && isEligible && hasDraftChanges
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    availabilityCard
                    rateRangeCard
                    requirementsCard
                }
                .padding()
            }
            .navigationTitle("Ride Type")
            .navigationBarTitleDisplayMode(.inline)
        }
        .onAppear {
            draftPerMile = nil
            draftPerMinute = nil
        }
        .onChange(of: rideType) { _, _ in
            draftPerMile = nil
            draftPerMinute = nil
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(rideType, systemImage: icon)
                .font(.title2.weight(.bold))
            Text(pricing.purpose)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 24).fill(.regularMaterial))
    }

    private var availabilityCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Availability")
                        .font(.headline)
                    Text(isEligible ? "Approved for this ride type." : lockedMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(isSelected ? "Active" : "Paused") {
                    onToggle()
                }
                .font(.caption.weight(.bold))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Capsule().fill(isSelected ? Color.green.opacity(0.16) : Color(.systemGray5)))
                .foregroundStyle(isSelected ? .green : .secondary)
                .disabled(!isEligible)
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 20).fill(Color(.secondarySystemBackground)))
    }

    private var rateRangeCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Rate Range")
                    .font(.headline)
                Spacer()
                Label(rateStatusText, systemImage: rateStatusIcon)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(rateStatusColor)
            }
            rateEditor(
                title: "Per Mile",
                range: pricing.perMileRangeText,
                value: currentPerMile,
                bounds: pricing.minPerMile...pricing.maxPerMile,
                onChange: { draftPerMile = $0 }
            )
            rateEditor(
                title: "Per Minute",
                range: pricing.perMinuteRangeText,
                value: currentPerMinute,
                bounds: pricing.minPerMinute...pricing.maxPerMinute,
                onChange: { draftPerMinute = $0 }
            )
            Button {
                onSaveRate(currentPerMile, currentPerMinute)
                draftPerMile = nil
                draftPerMinute = nil
            } label: {
                Label(hasDraftChanges ? "Save Rate" : "Rate Saved", systemImage: hasDraftChanges ? "square.and.arrow.down.fill" : "checkmark.circle.fill")
                    .font(.headline.weight(.bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(canSaveRate ? AnyShapeStyle(Styles.rydrGradient) : AnyShapeStyle(Color(.systemGray4)))
                    )
                    .foregroundStyle(.white)
            }
            .disabled(!canSaveRate)
            if isOnline {
                Label("Rates may only be adjusted while offline.", systemImage: "lock.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 20).fill(Color(.secondarySystemBackground)))
    }

    private var requirementsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Requirements")
                .font(.headline)
            ForEach(requirements, id: \.self) { requirement in
                Label(requirement, systemImage: "checkmark.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 20).fill(Color(.secondarySystemBackground)))
    }

    private func rateEditor(
        title: String,
        range: String,
        value: Double,
        bounds: ClosedRange<Double>,
        onChange: @escaping (Double) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                    Text(range)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("$\(value, specifier: "%.2f")")
                    .font(.headline.monospacedDigit())
            }

            Stepper(
                value: Binding(get: { value }, set: onChange),
                in: bounds,
                step: 0.05
            ) {
                Text("Current Rate")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .disabled(isOnline || !isEligible)
        }
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
            if item == .community {
                DriverCashRydrHubView()
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
}
