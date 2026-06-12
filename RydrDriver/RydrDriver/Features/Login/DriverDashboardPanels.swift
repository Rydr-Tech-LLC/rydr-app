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
    var onFareInsights: () -> Void
    var onNotifications: () -> Void

    var body: some View {
        HStack(alignment: .center) {
            Button { withAnimation(.spring) { vm.showMenu.toggle() } } label: {
                Circle().fill(.regularMaterial)
                    .frame(width: 42, height: 42)
                    .overlay(Image(systemName: "line.3.horizontal").font(.title3.weight(.semibold)))
                    .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
            }

            Spacer()

            Button(action: onFareInsights) {
                VStack(spacing: 2) {
                    Text(currencyFormatter.string(from: vm.earningsToday as NSDecimalNumber) ?? "$0.00")
                        .font(.headline.monospacedDigit().weight(.bold))
                    Text(vm.isOnline ? "Online" : "Offline")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(vm.isOnline ? Color.green : Color.white.opacity(0.68))
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 10)
                .background(
                    Capsule()
                        .fill(Color.black.opacity(0.86))
                        .overlay(Capsule().stroke(Color.white.opacity(0.16), lineWidth: 1))
                )
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.22), radius: 16, y: 8)
            }
            .buttonStyle(.plain)

            Spacer()

            Button(action: onNotifications) {
                Circle().fill(.regularMaterial)
                    .frame(width: 42, height: 42)
                    .overlay {
                        ZStack(alignment: .topTrailing) {
                            Image(systemName: "bell.fill")
                                .font(.footnote)
                                .foregroundStyle(Color.blue)
                            Circle()
                                .fill(Color.red)
                                .frame(width: 9, height: 9)
                                .offset(x: 7, y: -7)
                        }
                    }
                    .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
            }
        }
        .padding(.top, 8)
    }
}

struct DriverRideWorkPanel: View {
    @ObservedObject var vm: DriverDashboardVM
    var onRideTypeSelected: (String) -> Void

    var body: some View {
        VStack(spacing: 12) {
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
                DriverRideTypeCommandPanel(vm: vm, onRideTypeSelected: onRideTypeSelected)
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

struct DriverGoOnlineButton: View {
    @ObservedObject var vm: DriverDashboardVM
    var onFiltersTapped: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onFiltersTapped) {
                Image(systemName: "slider.horizontal.3")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(Color.red)
                    .frame(width: 54, height: 54)
                    .background(.regularMaterial, in: Circle())
                    .overlay(Circle().stroke(Color.white.opacity(0.28), lineWidth: 1))
                    .shadow(color: .black.opacity(0.12), radius: 12, y: 6)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Ride filters")

            Button {
                if vm.isReadyToGoOnline || vm.isOnline {
                    vm.toggleOnline()
                } else if let reason = vm.goOnlineBlockReason {
                    vm.statusMessage = reason
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: vm.isOnline ? "pause.fill" : "power")
                        .font(.headline)
                    Text(vm.isOnline ? "GO OFFLINE" : "GO ONLINE")
                        .font(.headline.weight(.bold))
                        .tracking(0.4)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .background(goButtonBackground)
                .foregroundStyle(.white)
                .shadow(color: vm.hasSavedRateSettings || vm.isOnline ? Color.red.opacity(0.32) : Color.black.opacity(0.10), radius: 18, y: 8)
            }
            .accessibilityHint(vm.goOnlineBlockReason ?? (vm.isOnline ? "Tap to go offline" : "Tap to go online"))
        }
    }

    private var goButtonBackground: some View {
        Capsule()
            .fill(vm.hasSavedRateSettings || vm.isOnline ? AnyShapeStyle(Styles.rydrGradient) : AnyShapeStyle(Color(.systemGray3)))
            .overlay(Capsule().fill(Color.white.opacity(vm.hasSavedRateSettings || vm.isOnline ? 0.10 : 0.02)))
            .overlay(Capsule().stroke(Color.white.opacity(0.25), lineWidth: 1))
    }
}

struct DriverBottomStatusBar: View {
    @ObservedObject var vm: DriverDashboardVM

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: vm.isOnline ? "checkmark.circle.fill" : "location.circle.fill")
                .font(.title3)
                .foregroundStyle(vm.isOnline ? .green : .primary)
            VStack(alignment: .leading, spacing: 2) {
                Text(vm.isOnline ? "Online and accepting rides" : "Offline")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(vm.isOnline ? .green : .primary)
                Text(bottomStatusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer()
        }
        .padding(14)
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

    private func tierSort(_ lhs: String, _ rhs: String) -> Bool {
        let ordered = DriverDashboardVM.availableRideTypes
        return (ordered.firstIndex(of: lhs) ?? ordered.endIndex) < (ordered.firstIndex(of: rhs) ?? ordered.endIndex)
    }
}
