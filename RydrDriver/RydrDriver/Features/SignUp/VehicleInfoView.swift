//
//  VehicleInfoView.swift
//  Rydr Driver
//
//  Step 5 of driver signup: Vehicle & Documents. Reworked for the Vehicle
//  Library System (hybrid VIN decoder + Mission Control managed image
//  library) — drivers enter their VIN and tap "Decode Vehicle" instead of
//  typing make/model/year by hand, then pick a color from a fixed list and
//  see the matching generic factory-style vehicle image immediately. No
//  photo of the driver's actual vehicle is ever uploaded.
//

import SwiftUI
import PhotosUI

struct VehicleInfoView: View {
    @Binding var vin: String
    @Binding var decoded: DecodedVehicleInfo?
    @Binding var selectedColor: VehicleColor?
    @Binding var imageInfo: VehicleImageInfo?
    @Binding var plate: String
    @Binding var registrationDoc: PhotosPickerItem?
    @Binding var insuranceCard: PhotosPickerItem?

    var currentStep: Int = 5
    var totalSteps: Int = 8

    /// Called once the driver taps Continue with a fully decoded vehicle,
    /// chosen color, and resolved (or gracefully missing) image. The
    /// coordinator performs the authoritative `submitVehicleVin` write
    /// before calling this.
    var onNext: () -> Void

    @State private var isDecoding = false
    @State private var decodeError: String?
    @State private var isFetchingImage = false
    @State private var imageError: String?
    @State private var isSubmitting = false

    // Manual-entry fallback, used when VIN decode can't find the vehicle
    // (NHTSA has no data for it, the VIN was mistyped/unreadable on the
    // registration, etc.) so a driver is never fully blocked here.
    @State private var isManualVehicle = false
    @State private var showManualEntry = false
    @State private var manualMake = ""
    @State private var manualModel = ""
    @State private var manualModelOther = ""
    @State private var manualYear = ""
    @State private var manualTrim = ""
    @State private var manualFuelType: DriverVehicleFuelType = .gas

    private var eligibility: DriverVehicleEligibility? {
        guard let decoded else { return nil }
        return DriverVehicleEligibility.evaluate(
            make: decoded.make,
            model: decoded.model,
            year: decoded.year,
            fuelType: decoded.fuelType.rawValue
        )
    }

    private var isValid: Bool {
        decoded != nil
        && selectedColor != nil
        && !plate.trimmingCharacters(in: .whitespaces).isEmpty
        && registrationDoc != nil
        && insuranceCard != nil
        && !isDecoding && !isSubmitting
    }

    private var vinLooksValid: Bool {
        vin.trimmingCharacters(in: .whitespacesAndNewlines).count == 17
    }

    private var manualEntryIsValid: Bool {
        !manualMake.isEmpty
        && !manualModel.isEmpty
        && (manualModel != ManualVehicleCatalog.otherOption || !manualModelOther.trimmingCharacters(in: .whitespaces).isEmpty)
        && manualYear.count == 4 && Int(manualYear) != nil
    }

    private var resolvedManualModel: String {
        manualModel == ManualVehicleCatalog.otherOption
            ? manualModelOther.trimmingCharacters(in: .whitespaces)
            : manualModel
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                DriverOnboardingStepIndicator(currentStep: currentStep, totalSteps: totalSteps, stepTitle: "Vehicle & Documents")

                VStack(spacing: 8) {
                    Text("Vehicle & Documents")
                        .font(.system(size: 26, weight: .heavy, design: .rounded))
                        .foregroundStyle(Styles.rydrGradient)
                    Text("Enter your VIN and we'll pull the details automatically — no vehicle photo needed.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                vinEntrySection

                if decoded == nil {
                    manualEntryToggleSection
                    if showManualEntry {
                        manualEntrySection
                    }
                }

                if let decoded {
                    decodedSummarySection(decoded)
                    colorPickerSection
                    imagePreviewSection

                    if let eligibility {
                        eligibilityBanner(eligibility)
                    }

                    HStack {
                        Image(systemName: "number").foregroundColor(.gray)
                        TextField("Plate Number", text: $plate)
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(14)
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.gray.opacity(0.3), lineWidth: 1))

                    HStack(spacing: 14) {
                        PhotosPicker(selection: $registrationDoc, matching: .images) {
                            UploadBox(label: registrationDoc == nil ? "Upload Registration" : "Registration ✓", systemImage: registrationDoc == nil ? "doc.fill" : "checkmark.circle.fill")
                        }
                        PhotosPicker(selection: $insuranceCard, matching: .images) {
                            UploadBox(label: insuranceCard == nil ? "Upload Insurance" : "Insurance ✓", systemImage: insuranceCard == nil ? "doc.fill" : "checkmark.circle.fill")
                        }
                    }
                }

                SignupContinueButton(title: isSubmitting ? "Saving…" : "Continue", isEnabled: isValid, action: handleContinue)

                SignupInfoCard(
                    icon: "lock.shield.fill",
                    title: "Your information is secure",
                    message: "Vehicle documents are encrypted and used only to confirm your eligibility to drive."
                )

                Spacer(minLength: 8)
            }
            .padding(.horizontal, 24)
            .padding(.top, 6)
        }
        .background(Color(.systemBackground))
        .hideKeyboardOnTap()
    }

    // MARK: - Sections

    private var vinEntrySection: some View {
        VStack(spacing: 10) {
            HStack {
                Image(systemName: "barcode.viewfinder").foregroundColor(.gray)
                TextField("Vehicle Identification Number (VIN)", text: $vin)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .onChange(of: vin) { _, newValue in
                        if newValue.count > 17 {
                            vin = String(newValue.prefix(17))
                        }
                    }
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(14)
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.gray.opacity(0.3), lineWidth: 1))

            Button(action: decodeVin) {
                HStack {
                    if isDecoding {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: "wand.and.stars")
                    }
                    Text(isDecoding ? "Decoding…" : "Decode Vehicle")
                        .font(.headline)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(vinLooksValid && !isDecoding ? Color.black : Color.gray.opacity(0.4)))
                .foregroundStyle(.white)
            }
            .disabled(!vinLooksValid || isDecoding)

            if let decodeError {
                Text(decodeError)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private func decodedSummarySection(_ decoded: DecodedVehicleInfo) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            VStack(alignment: .leading, spacing: 2) {
                Text(decoded.summaryText).font(.subheadline.weight(.semibold))
                if let driveType = decoded.driveType, !driveType.isEmpty {
                    Text(driveType).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button(isManualVehicle ? "Edit" : "Re-decode") {
                self.decoded = nil
                self.selectedColor = nil
                self.imageInfo = nil
                if isManualVehicle {
                    showManualEntry = true
                }
                isManualVehicle = false
            }
            .font(.caption.weight(.semibold))
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.green.opacity(0.08)))
    }

    /// Shown beneath the VIN field whenever decode hasn't succeeded yet —
    /// lets a driver skip decode entirely (or recover from a failed decode)
    /// instead of being blocked from continuing signup.
    private var manualEntryToggleSection: some View {
        Button {
            showManualEntry.toggle()
        } label: {
            Text(showManualEntry ? "Hide manual entry" : "Can't decode your VIN? Enter vehicle details manually")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(decodeError != nil ? Color.red : .secondary)
                .underline()
        }
        .padding(.top, decodeError == nil ? 0 : 2)
    }

    private var manualEntrySection: some View {
        VStack(spacing: 10) {
            TextField("Year", text: $manualYear)
                .keyboardType(.numberPad)
                .onChange(of: manualYear) { _, newValue in
                    manualYear = String(newValue.filter(\.isNumber).prefix(4))
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(14)
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.gray.opacity(0.3), lineWidth: 1))

            dropdownField(
                title: "Make",
                selection: $manualMake,
                options: ManualVehicleCatalog.makes,
                placeholder: "Select make"
            ) { newMake in
                manualModel = ""
                manualModelOther = ""
            }

            dropdownField(
                title: "Model",
                selection: $manualModel,
                options: ManualVehicleCatalog.models(for: manualMake),
                placeholder: manualMake.isEmpty ? "Select make first" : "Select model"
            )
            .disabled(manualMake.isEmpty)

            if manualModel == ManualVehicleCatalog.otherOption {
                TextField("Model name", text: $manualModelOther)
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(14)
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.gray.opacity(0.3), lineWidth: 1))
            }

            TextField("Trim (optional)", text: $manualTrim)
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(14)
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.gray.opacity(0.3), lineWidth: 1))

            Picker("Fuel type", selection: $manualFuelType) {
                ForEach(DriverVehicleFuelType.allCases) { type in
                    Text(type.rawValue).tag(type)
                }
            }
            .pickerStyle(.segmented)

            Button("Use these details") {
                useManualEntry()
            }
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(manualEntryIsValid ? Color.black : Color.gray.opacity(0.4)))
            .foregroundStyle(.white)
            .disabled(!manualEntryIsValid)

            Text("We'll have this vehicle reviewed since the details weren't pulled automatically.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 4)
    }

    /// A text-field-styled dropdown (native iOS Menu picker) used for the
    /// manual-entry Make/Model fields — keeps manual entries constrained to
    /// a known list instead of free-typed strings that could break
    /// eligibility matching or image lookups.
    private func dropdownField(
        title: String,
        selection: Binding<String>,
        options: [String],
        placeholder: String,
        onSelect: ((String) -> Void)? = nil
    ) -> some View {
        Menu {
            ForEach(options, id: \.self) { option in
                Button(option) {
                    selection.wrappedValue = option
                    onSelect?(option)
                }
            }
        } label: {
            HStack {
                Text(selection.wrappedValue.isEmpty ? placeholder : selection.wrappedValue)
                    .foregroundStyle(selection.wrappedValue.isEmpty ? .secondary : .primary)
                Spacer()
                Image(systemName: "chevron.down")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(14)
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.gray.opacity(0.3), lineWidth: 1))
        }
        .accessibilityLabel(title)
    }

    private var colorPickerSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Vehicle color").font(.subheadline.weight(.semibold))
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 10) {
                ForEach(VehicleColor.allCases) { color in
                    Button {
                        selectColor(color)
                    } label: {
                        VStack(spacing: 6) {
                            Circle()
                                .fill(color.swatch)
                                .frame(width: 30, height: 30)
                                .overlay(Circle().stroke(Color.gray.opacity(0.3), lineWidth: 1))
                                .overlay(
                                    selectedColor == color
                                        ? Circle().stroke(Styles.rydrGradient, lineWidth: 3)
                                        : nil
                                )
                            Text(color.rawValue).font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var imagePreviewSection: some View {
        if isFetchingImage {
            ProgressView("Finding your vehicle's image…")
                .frame(maxWidth: .infinity)
                .padding()
        } else if let imageInfo {
            VStack(spacing: 8) {
                if let urlString = imageInfo.imageUrl, let url = URL(string: urlString) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().scaledToFit()
                        case .failure:
                            vehiclePlaceholderIcon
                        default:
                            ProgressView()
                        }
                    }
                    .frame(height: 140)
                    .frame(maxWidth: .infinity)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(.systemGray6)))

                    if imageInfo.status == "fallback" {
                        Text("Showing a similar vehicle image — your exact color photo isn't available yet.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                } else {
                    VStack(spacing: 6) {
                        vehiclePlaceholderIcon
                        Text("Vehicle image not yet available.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(height: 140)
                    .frame(maxWidth: .infinity)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(.systemGray6)))
                }
            }
        } else if let imageError {
            Text(imageError).font(.footnote).foregroundStyle(.red)
        }
    }

    private var vehiclePlaceholderIcon: some View {
        Image(systemName: "car.fill")
            .font(.system(size: 36))
            .foregroundStyle(.secondary)
    }

    private func eligibilityBanner(_ eligibility: DriverVehicleEligibility) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.seal.fill").foregroundStyle(Styles.rydrGradient)
                Text("Eligible ride types").font(.headline)
            }
            if eligibility.eligibleRideTypes.isEmpty {
                Text("Manual review required before this vehicle can receive standard Rydr requests.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                HStack {
                    ForEach(eligibility.eligibleRideTypes, id: \.self) { rideType in
                        Text(rideType)
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(Color.red.opacity(0.14)))
                            .foregroundStyle(.red)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(.secondarySystemBackground)))
    }

    // MARK: - Actions

    private func decodeVin() {
        decodeError = nil
        isDecoding = true
        Task {
            do {
                let result = try await VehicleLibraryClient.decodeVin(vin)
                await MainActor.run {
                    decoded = result
                    selectedColor = nil
                    imageInfo = nil
                    isDecoding = false
                }
            } catch {
                await MainActor.run {
                    decodeError = error.localizedDescription
                    isDecoding = false
                }
            }
        }
    }

    private func useManualEntry() {
        guard manualEntryIsValid else { return }
        decoded = DecodedVehicleInfo(
            vin: vin.trimmingCharacters(in: .whitespacesAndNewlines),
            make: manualMake,
            model: resolvedManualModel,
            year: manualYear,
            trim: manualTrim.trimmingCharacters(in: .whitespaces).isEmpty ? nil : manualTrim.trimmingCharacters(in: .whitespaces),
            bodyStyle: nil,
            driveType: nil,
            fuelType: manualFuelType
        )
        isManualVehicle = true
        showManualEntry = false
        decodeError = nil
        selectedColor = nil
        imageInfo = nil
    }

    private func selectColor(_ color: VehicleColor) {
        selectedColor = color
        guard let decoded else { return }
        imageError = nil
        isFetchingImage = true
        Task {
            do {
                let result = try await VehicleLibraryClient.getVehicleImage(decoded: decoded, color: color)
                await MainActor.run {
                    imageInfo = result
                    isFetchingImage = false
                }
            } catch {
                await MainActor.run {
                    imageError = error.localizedDescription
                    isFetchingImage = false
                }
            }
        }
    }

    private func handleContinue() {
        guard let selectedColor, let decoded else { return }
        isSubmitting = true
        Task {
            do {
                let result: VehicleImageInfo
                if isManualVehicle {
                    let manualInfo = ManualVehicleInfo(
                        vin: decoded.vin.isEmpty ? nil : decoded.vin,
                        make: decoded.make,
                        model: decoded.model,
                        year: decoded.year,
                        trim: decoded.trim,
                        fuelType: decoded.fuelType
                    )
                    result = try await VehicleLibraryClient.submitVehicleManual(manualInfo, color: selectedColor)
                } else {
                    result = try await VehicleLibraryClient.submitVehicleVin(vin: vin, color: selectedColor)
                }
                await MainActor.run {
                    imageInfo = result
                    isSubmitting = false
                    onNext()
                }
            } catch {
                await MainActor.run {
                    decodeError = error.localizedDescription
                    isSubmitting = false
                }
            }
        }
    }
}

/// Backs the manual-entry Make/Model dropdowns. Covers the makes/models
/// `DriverVehicleEligibility` already recognizes (so a manually-entered
/// vehicle's eligibility matches what a decoded one would get) plus an
/// "Other" escape hatch for anything not listed.
private enum ManualVehicleCatalog {
    static let otherOption = "Other"

    static let makes: [String] = [
        "Acura", "Audi", "BMW", "Buick", "Cadillac", "Chevrolet", "Chrysler",
        "Dodge", "Ford", "Genesis", "GMC", "Honda", "Hyundai", "INFINITI",
        "Jeep", "Kia", "Lexus", "Lincoln", "Mazda", "Mercedes-Benz",
        "Mitsubishi", "Nissan", "Subaru", "Tesla", "Toyota", "Volkswagen",
        "Volvo", otherOption
    ]

    private static let modelsByMake: [String: [String]] = [
        "Honda": ["Accord", "Civic", "CR-V", "HR-V", "Odyssey", "Pilot"],
        "Toyota": ["Camry", "Corolla", "RAV4", "Highlander", "Sienna", "Prius"],
        "Nissan": ["Altima", "Sentra", "Rogue", "Maxima", "Armada"],
        "Hyundai": ["Elantra", "Sonata", "Tucson", "Santa Fe", "Palisade"],
        "Kia": ["Soul", "Sportage", "Sorento", "Telluride", "EV6"],
        "Chevrolet": ["Malibu", "Equinox", "Tahoe", "Suburban", "Bolt"],
        "Ford": ["Fusion", "Escape", "Explorer", "Expedition", "Mustang Mach-E"],
        "Tesla": ["Model 3", "Model Y", "Model S", "Model X"],
        "Mazda": ["Mazda3", "CX-5", "CX-30", "CX-9"],
        "Subaru": ["Impreza", "Forester", "Outback", "Ascent"],
        "Volkswagen": ["Jetta", "Passat", "Tiguan", "Atlas"],
        "Buick": ["Enclave", "Encore"],
        "GMC": ["Yukon", "Acadia"],
        "Cadillac": ["Escalade"],
        "Lincoln": ["Navigator"],
        "Dodge": ["Grand Caravan"],
        "Chrysler": ["Pacifica"]
    ]

    /// Returns the curated model list for `make` with "Other" always
    /// appended, or just `["Other"]` if no make is selected yet / the make
    /// has no curated list.
    static func models(for make: String) -> [String] {
        guard !make.isEmpty else { return [otherOption] }
        return (modelsByMake[make] ?? []) + [otherOption]
    }
}

private extension VehicleColor {
    var swatch: Color {
        switch self {
        case .black: return .black
        case .white: return .white
        case .silver: return Color(white: 0.75)
        case .gray: return .gray
        case .blue: return .blue
        case .red: return .red
        case .green: return .green
        case .brown: return .brown
        case .gold: return Color(red: 0.83, green: 0.69, blue: 0.22)
        case .yellow: return .yellow
        case .orange: return .orange
        }
    }
}
