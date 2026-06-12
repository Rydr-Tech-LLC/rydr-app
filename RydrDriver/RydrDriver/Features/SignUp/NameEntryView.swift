import SwiftUI

struct NameEntryView: View {
    @Binding var firstName: String
    @Binding var lastName: String
    @Binding var preferredName: String

    var onContinueWithForm: () -> Void

    @State private var errorMessage = ""
    @State private var isSaving = false

    var body: some View {
        VStack(spacing: 25) {
            Text("Tell us your name")
                .font(.title)
                .fontWeight(.bold)
                .foregroundStyle(
                    LinearGradient(
                        colors: [.red, Color(red: 0.5, green: 0, blue: 0.13).opacity(0.7)],
                        startPoint: .leading, endPoint: .trailing
                    )
                )

            TextField("First Name", text: $firstName)
                .textFieldStyle(.roundedBorder)

            TextField("Last Name", text: $lastName)
                .textFieldStyle(.roundedBorder)

            TextField("Preferred Name (optional)", text: $preferredName)
                .textFieldStyle(.roundedBorder)

            Button(isSaving ? "Saving..." : "Continue") {
                onContinueWithForm()
            }
            .disabled(isSaving)
            .buttonStyle(.borderedProminent)
            .tint(.red)

            if !errorMessage.isEmpty {
                Text(errorMessage)
                    .foregroundColor(.red)
                    .font(.caption)
            }

            Spacer()
        }
        .padding()
    }
}
