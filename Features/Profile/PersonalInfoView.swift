//
//  PersonalInfoView.swift
//  RydrPlayground
//
//  Created by Khris Nunnally on 8/18/25.
//
import SwiftUI
import FirebaseAuth
import FirebaseFirestore

struct PersonalInfoView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var session: UserSessionManager

    // Original values to detect changes
    @State private var original: RiderInfo = .empty

    // Current form values
    @State private var info: RiderInfo = .empty

    // Per-field edit toggles
    @State private var editPreferred = false
    @State private var editEmail = false
    @State private var editPhone = false
    @State private var editStreet = false
    @State private var editLine2 = false
    @State private var editCity = false
    @State private var editState = false
    @State private var editZip = false

    @State private var saving = false
    @State private var errorText = ""

    private let states = [
        "AL","AK","AZ","AR","CA","CO","CT","DE","FL","GA",
        "HI","ID","IL","IN","IA","KS","KY","LA","ME","MD",
        "MA","MI","MN","MS","MO","MT","NE","NV","NH","NJ",
        "NM","NY","NC","ND","OH","OK","OR","PA","RI","SC",
        "SD","TN","TX","UT","VT","VA","WA","WV","WI","WY"
    ]

    var body: some View {
        Form {
            // LEGAL NAME (locked)
            Section("Legal Name (not editable)") {
                DisabledRow(title: "First Name", value: info.firstName)
                DisabledRow(title: "Last Name",  value: info.lastName)
            }

            // Preferred Name
            Section("Preferred Name") {
                EditableTextRow(title: "Preferred Name", text: $info.preferredName, isEditing: $editPreferred)
            }

            // Contact
            Section("Contact") {
                EditableTextRow(title: "Email", text: $info.email, keyboard: .emailAddress, autocap: .never, isEditing: $editEmail)
                EditableTextRow(title: "Phone", text: $info.phone, keyboard: .phonePad, isEditing: $editPhone)
            }

            // Address
            Section("Address") {
                EditableTextRow(title: "Street", text: $info.street, isEditing: $editStreet)
                EditableTextRow(title: "Apt / Unit (optional)", text: $info.line2, isEditing: $editLine2)
                EditableTextRow(title: "City", text: $info.city, isEditing: $editCity)
                EditablePickerRow(title: "State", value: $info.state, options: states, isEditing: $editState)
                EditableTextRow(title: "ZIP", text: $info.zip, keyboard: .numberPad, isEditing: $editZip)
            }

            if !errorText.isEmpty {
                Text(errorText).foregroundColor(.red)
            }

            Button(saving ? "Saving..." : "Save Changes", action: save)
                .disabled(saving || !hasChanges)
        }
        .navigationTitle("Personal Information")
        .onAppear(perform: load)
    }

    private var hasChanges: Bool { info != original }

    private func load() {
        guard let uid = RydrWorkspace.auth.currentUser?.uid else { return }
        RydrWorkspace.firestore.collection("riders").document(uid).getDocument { snap, _ in
            guard let d = snap?.data() else { return }
            var i = RiderInfo.empty
            i.firstName      = d["firstName"] as? String ?? ""
            i.lastName       = d["lastName"]  as? String ?? ""
            i.preferredName  = d["preferredName"] as? String ?? ""
            i.email          = d["email"] as? String ?? ""
            i.phone          = d["phoneNumber"] as? String ?? ""
            if let addr = d["address"] as? [String: Any] {
                i.street = addr["street"] as? String ?? ""
                i.line2  = addr["line2"]  as? String ?? ""
                i.city   = addr["city"]   as? String ?? ""
                i.state  = addr["state"]  as? String ?? ""
                i.zip    = addr["zip"]    as? String ?? ""
            }
            original = i
            info = i
        }
    }

    private func save() {
        saving = true
        errorText = ""

        session.updatePersonalInfo(
            preferredName: info.preferredName,
            email: info.email,
            phone: info.phone,
            street: info.street,
            line2: info.line2,
            city: info.city,
            state: info.state,
            zip: info.zip
        ) { err in
            saving = false
            if let err = err {
                errorText = "Save failed: \(err.localizedDescription)"
            } else {
                // Refresh session so greeting updates immediately
                session.loadUserProfile()
                original = info
                dismiss()
            }
        }
    }
}

// MARK: - Model
private struct RiderInfo: Equatable {
    var firstName = ""
    var lastName  = ""
    var preferredName = ""
    var email = ""
    var phone = ""
    var street = ""
    var line2  = ""
    var city   = ""
    var state  = ""
    var zip    = ""
    static let empty = RiderInfo()
}

// MARK: - Reusable Rows
private struct DisabledRow: View {
    let title: String
    let value: String
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value.isEmpty ? "—" : value)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(.quaternaryLabel), lineWidth: 1))
        }
    }
}

private struct EditableTextRow: View {
    let title: String
    @Binding var text: String
    var keyboard: UIKeyboardType = .default
    var autocap: TextInputAutocapitalization = .sentences
    @Binding var isEditing: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button {
                    withAnimation { isEditing.toggle() }
                } label: {
                    Image(systemName: isEditing ? "checkmark.circle.fill" : "pencil")
                        .foregroundColor(.red)
                }
                .buttonStyle(.plain)
            }

            if isEditing {
                TextField(title, text: $text)
                    .textInputAutocapitalization(autocap)
                    .keyboardType(keyboard)
                    .padding(12)
                    .background(Color(.systemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(.red.opacity(0.25)))
            } else {
                Text(text.isEmpty ? "—" : text)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(.quaternaryLabel), lineWidth: 1))
            }
        }
    }
}

private struct EditablePickerRow: View {
    let title: String
    @Binding var value: String
    let options: [String]
    @Binding var isEditing: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button {
                    withAnimation { isEditing.toggle() }
                } label: {
                    Image(systemName: isEditing ? "checkmark.circle.fill" : "pencil")
                        .foregroundColor(.red)
                }
                .buttonStyle(.plain)
            }

            if isEditing {
                Picker(title, selection: $value) {
                    ForEach(options, id: \.self) { Text($0).tag($0) }
                }
                .pickerStyle(.navigationLink)
            } else {
                Text(value.isEmpty ? "—" : value)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(.quaternaryLabel), lineWidth: 1))
            }
        }
    }
}

