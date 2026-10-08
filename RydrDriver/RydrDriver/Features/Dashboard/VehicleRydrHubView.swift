import SwiftUI
import PhotosUI
import FirebaseAuth
import FirebaseFirestore

struct VehicleRydrHubView: View {
    @ObservedObject var vm: DriverDashboardVM
    @State private var showAddVehicle = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 14) {
                vehicleSection
                rideQualificationsSection
            }
            .padding(.horizontal, 18)
            .padding(.top, 12)
            .padding(.bottom, 28)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Vehicle & Rydr Hub")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showAddVehicle = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .foregroundStyle(Styles.rydrGradient)
                }
                .accessibilityLabel("Add a new vehicle")
            }
        }
        .sheet(isPresented: $showAddVehicle) {
            AddDriverVehicleSheet {
                showAddVehicle = false
            }
        }
    }

    private var vehicleSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(icon: "car.fill", title: "My Vehicle", trailingIcon: "trash")

            HStack(alignment: .center, spacing: 14) {
                vehicleImage
                    .frame(width: 188, height: 118)

                VStack(alignment: .leading, spacing: 10) {
                    Text(vm.vehicleSummaryText ?? "Add your vehicle")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)

                    if let detail = vm.vehicleDetailText {
                        Text(detail)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }

                    vehicleFact(icon: "paintpalette", title: "Color", value: vm.vehicleColor ?? "Not set")
                    vehicleFact(icon: "rectangle.and.text.magnifyingglass", title: "License Plate", value: vm.vehiclePlateText ?? "Not set")
                    vehicleFact(icon: "checkmark.shield", title: "Insurance", value: statusText(vm.insuranceStatus), tint: statusTint(vm.insuranceStatus))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(.secondarySystemGroupedBackground)))
            .overlay(alignment: .topLeading) {
                if vm.vehicleSummaryText != nil {
                    Label("Current", systemImage: "checkmark.circle")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.green)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(Color.green.opacity(0.12)))
                        .padding(10)
                }
            }

            Button {
                showAddVehicle = true
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "plus.circle.fill")
                        .foregroundStyle(Styles.rydrGradient)
                    Text("Add a New Vehicle")
                        .font(.subheadline.weight(.bold))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                }
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(.secondarySystemGroupedBackground)))
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color(.systemBackground)))
    }

    private var rideQualificationsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                sectionHeader(icon: "rosette", title: "Ride Type Qualifications")
                Text("Your current approval status for each ride type")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ForEach(DriverDashboardVM.availableRideTypes, id: \.self) { rideType in
                VehicleRydrRideTypeRow(
                    rideType: rideType,
                    vm: vm,
                    status: rideStatus(for: rideType)
                )
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color(.systemBackground)))
    }

    @ViewBuilder
    private var vehicleImage: some View {
        if let rawURL = vm.vehicleImageURL,
           let url = URL(string: rawURL),
           !rawURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFit()
                default:
                    vehicleFallbackImage
                }
            }
        } else {
            vehicleFallbackImage
        }
    }

    private var vehicleFallbackImage: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.red.opacity(0.08))
            Image(systemName: "car.side.fill")
                .font(.system(size: 46, weight: .semibold))
                .foregroundStyle(Styles.rydrGradient)
        }
    }

    private func sectionHeader(icon: String, title: String, trailingIcon: String? = nil) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(Styles.rydrGradient)
                .frame(width: 22)
            Text(title)
                .font(.headline.weight(.bold))
            Spacer()
            if let trailingIcon {
                Image(systemName: trailingIcon)
                    .foregroundStyle(Styles.rydrGradient)
                    .frame(width: 34, height: 34)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color(.secondarySystemGroupedBackground)))
                    .accessibilityHidden(true)
            }
        }
    }

    private func vehicleFact(icon: String, title: String, value: String, tint: Color = .primary) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(tint)
            }
        }
    }

    private func rideStatus(for rideType: String) -> VehicleRydrRideStatus {
        if vm.selectedRideTypes.contains(rideType) { return .approved }
        if vm.eligibleRideTypes.contains(rideType) { return .available }
        return .locked
    }

    private func statusText(_ status: String) -> String {
        switch status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "approved", "verified", "valid": return "Verified"
        case "pending", "review": return "Pending"
        case "rejected", "failed": return "Needs review"
        default: return "Not set"
        }
    }

    private func statusTint(_ status: String) -> Color {
        switch status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "approved", "verified", "valid": return .green
        case "pending", "review": return .orange
        case "rejected", "failed": return .red
        default: return .secondary
        }
    }
}

private enum VehicleRydrRideStatus {
    case approved
    case available
    case locked

    var title: String {
        switch self {
        case .approved: return "Approved"
        case .available: return "Eligible"
        case .locked: return "Locked"
        }
    }

    var icon: String {
        switch self {
        case .approved: return "checkmark"
        case .available: return "plus"
        case .locked: return "lock.fill"
        }
    }

    var tint: Color {
        switch self {
        case .approved, .available: return .green
        case .locked: return .secondary
        }
    }

    var background: Color {
        switch self {
        case .approved, .available: return Color.green.opacity(0.12)
        case .locked: return Color(.tertiarySystemGroupedBackground)
        }
    }
}

private struct VehicleRydrRideTypeRow: View {
    let rideType: String
    @ObservedObject var vm: DriverDashboardVM
    let status: VehicleRydrRideStatus

    private var metadata: RydrRideTierMetadata {
        RydrRideTierCatalog.metadata(for: rideType)
    }

    var body: some View {
        Button {
            if status != .locked {
                vm.toggleRideType(rideType)
            }
        } label: {
            HStack(spacing: 12) {
                vehicleThumb

                VStack(alignment: .leading, spacing: 4) {
                    Text(metadata.title)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.primary)
                    Text(metadata.purpose)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    if let suggestion = vm.suggestedRate(for: rideType) {
                        Text("Suggested \(suggestion.perMile, format: .currency(code: "USD"))/mi · \(suggestion.perMinute, format: .currency(code: "USD"))/min · \(suggestion.minimumFare, format: .currency(code: "USD")) minimum")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Suggested rates load from backend demand")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Label(status.title, systemImage: status.icon)
                    .font(.caption2.weight(.bold))
                    .labelStyle(.titleAndIcon)
                    .foregroundStyle(status.tint)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(status.background))

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(.secondarySystemGroupedBackground)))
            .overlay(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(status.tint)
                    .frame(width: 3)
                    .padding(.vertical, 9)
                    .opacity(status == .locked ? 0.35 : 1)
            }
        }
        .buttonStyle(.plain)
        .disabled(status == .locked)
    }

    @ViewBuilder
    private var vehicleThumb: some View {
        if let rawURL = vm.vehicleImageURL,
           let url = URL(string: rawURL),
           !rawURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFit()
                default:
                    Image(systemName: "car.side.fill").foregroundStyle(Styles.rydrGradient)
                }
            }
            .frame(width: 58, height: 38)
        } else {
            Image(systemName: "car.side.fill")
                .font(.title2.weight(.semibold))
                .foregroundStyle(Styles.rydrGradient)
                .frame(width: 58, height: 38)
        }
    }
}

private struct AddDriverVehicleSheet: View {
    let onComplete: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var vin = ""
    @State private var decodedVehicle: DecodedVehicleInfo?
    @State private var selectedColor: VehicleColor?
    @State private var imageInfo: VehicleImageInfo?
    @State private var plate = ""
    @State private var registrationDoc: PhotosPickerItem?
    @State private var insuranceCard: PhotosPickerItem?
    @State private var saveError: String?

    var body: some View {
        NavigationStack {
            VehicleInfoView(
                vin: $vin,
                decoded: $decodedVehicle,
                selectedColor: $selectedColor,
                imageInfo: $imageInfo,
                plate: $plate,
                registrationDoc: $registrationDoc,
                insuranceCard: $insuranceCard
            ) {
                saveVehicleEligibility()
            }
            .navigationTitle("Add Vehicle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .alert("Vehicle", isPresented: Binding(
                get: { saveError != nil },
                set: { if !$0 { saveError = nil } }
            )) {
                Button("OK", role: .cancel) { saveError = nil }
            } message: {
                Text(saveError ?? "")
            }
        }
    }

    private func saveVehicleEligibility() {
        guard let uid = Auth.auth().currentUser?.uid else {
            saveError = "Sign in before adding a vehicle."
            return
        }
        guard decodedVehicle != nil else {
            onComplete()
            dismiss()
            return
        }

        _ = uid
        Task { @MainActor in
            do {
                try await RydrBackendService.updateVehiclePlate(plate.trimmingCharacters(in: .whitespacesAndNewlines))
                onComplete()
                dismiss()
            } catch {
                saveError = error.localizedDescription
            }
        }
    }
}
