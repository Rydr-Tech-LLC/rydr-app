import SwiftUI
import PhotosUI
import FirebaseAuth
import FirebaseFirestore

struct SavedDriverVehicle: Identifiable {
    let id: String
    let summary: String
    let color: String
    let plate: String
    let vin: String?
    let imageURL: String?
    init(id: String, data: [String: Any]) {
        self.id = id
        summary = [String(describing: data["year"] ?? ""), data["make"] as? String ?? "", data["model"] as? String ?? ""].filter { !$0.isEmpty }.joined(separator: " ")
        color = data["color"] as? String ?? "Not set"
        plate = data["plate"] as? String ?? "Not set"
        vin = data["vin"] as? String
        imageURL = data["imageUrl"] as? String ?? data["imageURL"] as? String
    }
}

struct VehicleRydrHubView: View {
    @ObservedObject var vm: DriverDashboardVM
    @State private var fixtureSeeded = false
    @State private var showAddVehicle = false
    @State private var showDeleteConfirmation = false
    @State private var vehicleToDelete: SavedDriverVehicle?
    @State private var deleteError: String?
    @State private var deletingVehicleID: String?

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
                #if DEBUG && targetEnvironment(simulator)
                if ProcessInfo.processInfo.arguments.contains("-RydrGarageUITest") {
                    vm.savedVehicles.append(SavedDriverVehicle(id: "fixture-saved", data: ["year": 2024, "make": "Land Rover", "model": "Range Rover", "color": "Black", "plate": "SECOND"]))
                }
                #endif
                showAddVehicle = false
            }
        }
        .onAppear {
            #if DEBUG && targetEnvironment(simulator)
            if ProcessInfo.processInfo.arguments.contains("-RydrGarageUITest") && !fixtureSeeded {
                fixtureSeeded = true
                vm.vehicleSummaryText = "2020 Honda Accord"
                vm.vehicleColor = "White"
                vm.vehiclePlateText = "CURRENT"
                vm.currentVehicleVin = "CURRENTVIN0000001"
            }
            #endif
        }
        .alert(deleteError == nil ? "Delete vehicle?" : "Could not delete vehicle", isPresented: Binding(
            get: { showDeleteConfirmation || deleteError != nil },
            set: { if !$0 { showDeleteConfirmation = false; deleteError = nil } }
        )) {
            if deleteError != nil {
                Button("OK", role: .cancel) { deleteError = nil }
            } else if let vehicle = vehicleToDelete {
                Button("Delete Vehicle", role: .destructive) { delete(vehicle) }
                Button("Cancel", role: .cancel) { vehicleToDelete = nil }
            }
        } message: {
            Text(deleteError ?? (vehicleToDelete?.id == "current" ? "Removing your current vehicle stops driving access until another vehicle is approved. Saved vehicles remain on your account." : "Remove this saved vehicle from your account?"))
        }
    }

    private func delete(_ vehicle: SavedDriverVehicle) {
        deletingVehicleID = vehicle.id
        vehicleToDelete = nil
        Task { @MainActor in
            do {
                #if DEBUG && targetEnvironment(simulator)
                if ProcessInfo.processInfo.arguments.contains("-RydrGarageUITest") {
                    if vehicle.id == "current" { vm.vehicleSummaryText = nil; vm.canGoOnline = false }
                    else { vm.savedVehicles.removeAll { $0.id == vehicle.id } }
                } else { try await VehicleLibraryClient.deleteVehicle(vehicle) }
                #else
                try await VehicleLibraryClient.deleteVehicle(vehicle)
                #endif
            }
            catch { deleteError = error.localizedDescription }
            deletingVehicleID = nil
        }
    }

    private var vehicleSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(icon: "car.fill", title: "My Vehicles")
            if vm.vehicleSummaryText != nil {
                vehicleCard(SavedDriverVehicle(id: "current", data: ["make": vm.vehicleSummaryText ?? "", "color": vm.vehicleColor ?? "", "plate": vm.vehiclePlateText ?? "", "vin": vm.currentVehicleVin ?? "", "imageUrl": vm.vehicleImageURL ?? ""]))
            }
            ForEach(vm.savedVehicles) { vehicle in vehicleCard(vehicle) }
            if vm.vehicleSummaryText == nil && vm.savedVehicles.isEmpty {
                Text("Add a vehicle to your account.").font(.subheadline).foregroundStyle(.secondary)
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

    private func vehicleCard(_ vehicle: SavedDriverVehicle) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(vehicle.id == "current" ? "Current" : "Saved — not current", systemImage: vehicle.id == "current" ? "checkmark.circle" : "car.fill")
                    .font(.caption.weight(.bold)).foregroundStyle(vehicle.id == "current" ? Color.green : Color.secondary)
                Spacer()
                Button(role: .destructive) { vehicleToDelete = vehicle; showDeleteConfirmation = true } label: {
                    Image(systemName: "trash").frame(width: 44, height: 44).contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Delete \(vehicle.summary)")
                .accessibilityIdentifier("deleteVehicle-\(vehicle.id)")
                .disabled(deletingVehicleID != nil)
            }
            HStack(spacing: 14) {
                AsyncImage(url: vehicle.imageURL.flatMap(URL.init(string:))) { image in
                    image.resizable().scaledToFit()
                } placeholder: { vehicleFallbackImage }
                .frame(width: 140, height: 95)
                VStack(alignment: .leading, spacing: 8) {
                    Text(vehicle.summary).font(.headline).accessibilityIdentifier("vehicleCard-\(vehicle.id)")
                    vehicleFact(icon: "paintpalette", title: "Color", value: vehicle.color)
                    vehicleFact(icon: "number", title: "License Plate", value: vehicle.plate)
                }
            }
            if vehicle.id != "current" {
                Text("Documents and approval required before driving with this vehicle.").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(.secondarySystemGroupedBackground)))
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

    private var vehicleFallbackImage: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.red.opacity(0.08))
            Image(systemName: "car.side.fill")
                .font(.system(size: 46, weight: .semibold))
                .foregroundStyle(Styles.rydrGradient)
        }
    }

    private func sectionHeader(icon: String, title: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(Styles.rydrGradient)
                .frame(width: 22)
            Text(title)
                .font(.headline.weight(.bold))
            Spacer()

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
                insuranceCard: $insuranceCard,
                addToGarage: true
            ) {
                saveVehicleEligibility()
            }
            .onAppear {
                #if DEBUG && targetEnvironment(simulator)
                if ProcessInfo.processInfo.arguments.contains("-RydrGarageUITest") {
                    vin = "SAL1P9EU0RA170245"
                    decodedVehicle = DecodedVehicleInfo(vin: vin, make: "Land Rover", model: "Range Rover", year: "2024", fuelType: .gas)
                    selectedColor = .black
                    plate = "SECOND"
                }
                #endif
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
        // VehicleInfoView has already saved a separate garage record through the backend.
        onComplete()
        dismiss()
    }
}
