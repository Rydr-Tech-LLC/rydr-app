import SwiftUI
import CoreLocation

enum RideTypePillStatus {
    case approved(String)
    case locked(String)
    case pending(String)

    var label: String {
        switch self {
        case .approved(let label), .locked(let label), .pending(let label):
            return label
        }
    }

    var icon: String {
        switch self {
        case .approved: return "checkmark.seal.fill"
        case .locked: return "lock.fill"
        case .pending: return "clock.fill"
        }
    }

    var color: Color {
        switch self {
        case .approved: return .green
        case .locked: return .secondary
        case .pending: return .orange
        }
    }
}

struct DriverTopBar: View {
    @ObservedObject var vm: DriverDashboardVM
    var buttonSize: CGFloat = 42
    var isCompact: Bool = false
    var onFareInsights: () -> Void
    var onNotifications: () -> Void

    var body: some View {
        HStack(alignment: .center) {
            Button { withAnimation(.spring) { vm.showMenu.toggle() } } label: {
                Circle().fill(.regularMaterial)
                    .frame(width: buttonSize, height: buttonSize)
                    .overlay(
                        Image(systemName: "line.3.horizontal")
                            .font((isCompact ? Font.body : Font.title3).weight(.semibold))
                            .foregroundStyle(Color.primary)
                    )
                    .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
            }
            .buttonStyle(.plain)

            Spacer()

            Button(action: onFareInsights) {
                VStack(spacing: 2) {
                    Text(currencyFormatter.string(from: vm.earningsToday as NSDecimalNumber) ?? "$0.00")
                        .font((isCompact ? Font.subheadline : Font.headline).monospacedDigit().weight(.black))
                    Text(statusText)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(vm.isOnline ? Color.green : Color.white.opacity(0.68))
                        .lineLimit(1)
                }
                .padding(.horizontal, isCompact ? 16 : 20)
                .padding(.vertical, isCompact ? 7 : 8)
                .frame(minWidth: isCompact ? 116 : 128)
                .background(
                    Capsule()
                        .fill(Color.black.opacity(0.88))
                        .overlay(Capsule().stroke(Color.white.opacity(0.16), lineWidth: 1))
                )
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.22), radius: 16, y: 8)
            }
            .buttonStyle(.plain)

            Spacer()

            Button(action: onNotifications) {
                Circle().fill(.regularMaterial)
                    .frame(width: buttonSize, height: buttonSize)
                    .overlay {
                        ZStack(alignment: .topTrailing) {
                            Image(systemName: "bell.fill")
                                .font(.footnote)
                                .foregroundStyle(Color.primary)
                            Circle()
                                .fill(Color.red)
                                .frame(width: 9, height: 9)
                                .offset(x: 7, y: -7)
                        }
                    }
                    .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
            }
            .buttonStyle(.plain)
        }
    }

    private var statusText: String {
        guard vm.isOnline else { return "Offline" }
        return vm.rideFilterPreferences.workZoneEnabled
            ? "Online · \(Int(vm.rideFilterPreferences.effectivePickupMiles.rounded())) mi zone"
            : "Online"
    }
}

struct DriverBoostedAreaBanner: View {
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "shield.lefthalf.filled.badge.checkmark")
                .font(.headline.weight(.black))
                .foregroundStyle(.white)
                .frame(width: 38, height: 38)
                .background(Circle().fill(Styles.rydrGradient))
                .shadow(color: Color.red.opacity(0.24), radius: 10, y: 5)

            VStack(alignment: .leading, spacing: 2) {
                Text("You're in a boosted area")
                    .font(.subheadline.weight(.black))
                    .foregroundStyle(.primary)
                Text("1.4x until 10:00 AM")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.red)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption.weight(.black))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.regularMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(Color.white.opacity(0.26), lineWidth: 1)
                )
        )
        .shadow(color: .black.opacity(0.10), radius: 14, y: 7)
    }
}

struct DriverRideWorkPanel: View {
    @ObservedObject var vm: DriverDashboardVM
    var onRideTypeSelected: (String) -> Void

    var body: some View {
        Group {
            if let request = vm.pendingRequests.first, vm.activeRide == nil {
                IncomingRideRequestCard(
                    request: request,
                    driverCoordinate: vm.lastLocation?.coordinate,
                    rate: vm.rate(for: request.rideType),
                    onAccept: { vm.accept(request) },
                    onDecline: { vm.decline(request) },
                    onTimeout: { vm.miss(request) }
                )
            } else {
                EmptyView()
            }
        }
        .frame(maxWidth: .infinity)
    }
}

struct DriverRideTypeCommandPanel: View {
    @ObservedObject var vm: DriverDashboardVM
    var onRideTypeSelected: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Rate Card")
                        .font(.headline)
                    Text(vm.statusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                if !vm.pendingRequests.isEmpty {
                    Text("\(vm.pendingRequests.count)")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(Color.green.opacity(0.16)))
                        .foregroundStyle(.green)
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(vm.eligibleRideTypes.sorted(by: tierSort), id: \.self) { rideType in
                        Button {
                            onRideTypeSelected(rideType)
                        } label: {
                            RideTypeFilterPill(
                                rideType: rideType,
                                status: rideTypeStatus(for: rideType),
                                isSelected: vm.selectedRideTypes.contains(rideType),
                                isEligible: true
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 2)
            }

            HStack(spacing: 8) {
                Label("\(vm.selectedRideTypes.count) active", systemImage: "slider.horizontal.3")
                Spacer()
                Label(vm.hasSavedRateSettings ? "Rate saved" : "Set rate", systemImage: vm.hasSavedRateSettings ? "checkmark.circle.fill" : "dollarsign.circle")
                    .foregroundStyle(vm.hasSavedRateSettings ? .green : .secondary)
            }
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.regularMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(Color.white.opacity(0.26), lineWidth: 1)
                )
        )
        .shadow(color: .black.opacity(0.14), radius: 18, y: 10)
    }

    private func rideTypeStatus(for rideType: String) -> RideTypePillStatus {
        guard vm.eligibleRideTypes.contains(rideType) else {
            switch rideType {
            case "Rydr Eco":
                return .locked("Vehicle Requirement Needed")
            case "Rydr XL":
                return .locked("Vehicle Requirement Needed")
            case "Rydr Prestine":
                return .pending("Driver Rating Required")
            case "Rydr Executive":
                return .pending("Application Required")
            default:
                return .locked("Pending Qualification")
            }
        }
        return .approved(vm.selectedRideTypes.contains(rideType) ? "Approved" : "Approved • Paused")
    }

    private func tierSort(_ lhs: String, _ rhs: String) -> Bool {
        let ordered = DriverDashboardVM.availableRideTypes
        return (ordered.firstIndex(of: lhs) ?? ordered.endIndex) < (ordered.firstIndex(of: rhs) ?? ordered.endIndex)
    }
}

struct RideTypeFilterPill: View {
    let rideType: String
    let status: RideTypePillStatus
    let isSelected: Bool
    let isEligible: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.caption)
                Text(rideType)
                    .font(.caption.weight(.bold))
            }
            HStack(spacing: 4) {
                Image(systemName: status.icon)
                    .font(.system(size: 9, weight: .bold))
                Text(status.label)
                    .font(.system(size: 10, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(status.color)
        }
        .frame(width: 128, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(isSelected ? Color.red.opacity(0.15) : Color(.systemBackground).opacity(0.72))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(isSelected ? Color.red.opacity(0.35) : Color.black.opacity(0.06), lineWidth: 1)
        )
        .foregroundStyle(isEligible ? .primary : .secondary)
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

struct DriverDashboardActionDock: View {
    @ObservedObject var vm: DriverDashboardVM
    var isCompact: Bool = false
    var onFiltersTapped: () -> Void
    var onRateCardTapped: () -> Void
    var onCashHubTapped: () -> Void
    var onProfileTapped: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: isCompact ? 6 : 10) {
            DriverDockIcon(
                title: "Filters",
                systemName: "slider.horizontal.3",
                isSelected: vm.rideFilterPreferences.workZoneEnabled || vm.rideFilterPreferences.hasDestinationFilter,
                isCompact: isCompact,
                badge: nil,
                action: onFiltersTapped
            )

            DriverDockIcon(
                title: "Rate Card",
                systemName: "dollarsign.circle",
                isSelected: vm.hasSavedRateSettings,
                isCompact: isCompact,
                badge: nil,
                action: onRateCardTapped
            )

            Button {
                if vm.isReadyToGoOnline || vm.isOnline {
                    vm.toggleOnline()
                } else if let reason = vm.goOnlineBlockReason {
                    vm.statusMessage = reason
                }
            } label: {
                VStack(spacing: 5) {
                    Image(systemName: vm.isOnline ? "pause.fill" : "power")
                        .font(.title3.weight(.black))
                    Text(vm.isOnline ? "Offline" : "Online")
                        .font(.caption2.weight(.black))
                }
                .foregroundStyle(.white)
                .frame(width: isCompact ? 54 : 58, height: isCompact ? 54 : 58)
                .background(Circle().fill(goButtonBackground))
                .overlay(Circle().stroke(Color.white.opacity(0.28), lineWidth: 1))
                .shadow(color: vm.hasSavedRateSettings || vm.isOnline ? Color.red.opacity(0.40) : Color.black.opacity(0.14), radius: 18, y: 8)
            }
            .buttonStyle(.plain)
            .accessibilityHint(vm.goOnlineBlockReason ?? (vm.isOnline ? "Tap to go offline" : "Tap to go online"))

            DriverDockIcon(
                title: "Cash Hub",
                systemName: "building.columns",
                isSelected: false,
                isCompact: isCompact,
                badge: nil,
                action: onCashHubTapped
            )

            DriverDockIcon(
                title: "Profile",
                systemName: "person.crop.circle.fill",
                isSelected: false,
                isCompact: isCompact,
                badge: nil,
                action: onProfileTapped
            )
        }
        .padding(.horizontal, isCompact ? 9 : 10)
        .padding(.vertical, isCompact ? 6 : 8)
        .frame(maxHeight: isCompact ? 72 : 78)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(.regularMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(Color.white.opacity(0.30), lineWidth: 1)
                )
        )
        .shadow(color: .black.opacity(0.16), radius: 18, y: 10)
    }

    private var goButtonBackground: AnyShapeStyle {
        vm.hasSavedRateSettings || vm.isOnline
            ? AnyShapeStyle(Styles.rydrGradient)
            : AnyShapeStyle(Color(.systemGray3))
    }
}

private struct DriverDockIcon: View {
    let title: String
    let systemName: String
    let isSelected: Bool
    let isCompact: Bool
    let badge: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: systemName)
                        .font((isCompact ? Font.subheadline : Font.headline).weight(.black))
                        .foregroundStyle(isSelected ? Color.red : Color.primary)
                        .frame(width: isCompact ? 36 : 40, height: isCompact ? 32 : 34)
                        .background(
                            RoundedRectangle(cornerRadius: 15, style: .continuous)
                                .fill(isSelected ? Color.red.opacity(0.10) : Color(.systemBackground).opacity(0.76))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 15, style: .continuous)
                                .stroke(isSelected ? Color.red.opacity(0.28) : Color.black.opacity(0.06), lineWidth: 1)
                        )

                    if let badge {
                        Text(badge)
                            .font(.system(size: 9, weight: .black))
                            .foregroundStyle(.white)
                            .frame(width: 16, height: 16)
                            .background(Circle().fill(Color.red))
                            .offset(x: 5, y: -5)
                    }
                }

                Text(title)
                    .font(.system(size: isCompact ? 8 : 9, weight: .bold))
                    .foregroundStyle(isSelected ? Color.red : Color.primary.opacity(0.78))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }
}

struct DriverBottomStatusBar: View {
    @ObservedObject var vm: DriverDashboardVM

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "scope")
                .font(.title3)
                .foregroundStyle(Color.red)
            VStack(alignment: .leading, spacing: 2) {
                Text(activeFilterSummary)
                    .font(.subheadline.weight(.black))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(bottomStatusMessage)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Image(systemName: "chevron.up")
                .font(.caption.weight(.black))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.regularMaterial)
                .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.white.opacity(0.22), lineWidth: 1))
        )
    }

    private var bottomStatusMessage: String {
        if vm.isSearchingForRides {
            return "Standby. Searching for \(vm.selectedRideTypes.sorted(by: tierSort).joined(separator: ", ")) rides."
        }
        if let reason = vm.goOnlineBlockReason {
            return reason
        }
        return "Rate saved. Go online when ready."
    }

    private var activeFilterSummary: String {
        let workZone = vm.rideFilterPreferences.workZoneEnabled
            ? "\(Int(vm.rideFilterPreferences.effectivePickupMiles.rounded())) mi"
            : "Off"
        let destination = vm.rideFilterPreferences.hasDestinationFilter ? "On" : "Off"
        return "Work Zone: \(workZone) · Destination: \(destination)"
    }

    private func tierSort(_ lhs: String, _ rhs: String) -> Bool {
        let ordered = DriverDashboardVM.availableRideTypes
        return (ordered.firstIndex(of: lhs) ?? ordered.endIndex) < (ordered.firstIndex(of: rhs) ?? ordered.endIndex)
    }
}
