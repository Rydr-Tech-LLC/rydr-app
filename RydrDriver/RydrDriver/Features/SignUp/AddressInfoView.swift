//
//  AddressInfoView.swift
//  Rydr Driver
//
//  Step 3 of driver signup: "Where Are You Located?" — restyled with a
//  shared step indicator and reassurance card to match the premium
//  onboarding mockup. Field styling already matched the design language, so
//  this keeps it and rounds it out with the indicator/info card/Continue.
//

import SwiftUI
import FirebaseAuth
import FirebaseFirestore

struct AddressInfoView: View {
    @Binding var street: String
    @Binding var addressLine2: String
    @Binding var city: String
    @Binding var state: String
    @Binding var zipCode: String

    var currentStep: Int = 3
    var totalSteps: Int = 8

    var onNext: () -> Void

    private let usStates = [
        "AL","AK","AZ","AR","CA","CO","CT","DE","FL","GA","HI","ID","IL","IN","IA",
        "KS","KY","LA","ME","MD","MA","MI","MN","MS","MO","MT","NE","NV","NH","NJ",
        "NM","NY","NC","ND","OH","OK","OR","PA","RI","SC","SD","TN","TX","UT","VT",
        "VA","WA","WV","WI","WY"
    ]

    private var isValid: Bool {
        !street.trimmingCharacters(in: .whitespaces).isEmpty
        && !city.trimmingCharacters(in: .whitespaces).isEmpty
        && !state.trimmingCharacters(in: .whitespaces).isEmpty
        && zipCode.count >= 5
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                DriverOnboardingStepIndicator(currentStep: currentStep, totalSteps: totalSteps, stepTitle: "Your Address")

                VStack(spacing: 8) {
                    Text("Where Are You Located?")
                        .font(.system(size: 26, weight: .heavy, design: .rounded))
                        .foregroundStyle(Styles.rydrGradient)
                    Text("We use your address to confirm your driving area and identity.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                VStack(spacing: 14) {
                    iconField(icon: "house.fill", placeholder: "Street Address", text: $street)
                    iconField(icon: "number", placeholder: "Apt / Unit (optional)", text: $addressLine2)
                    iconField(icon: "building.2.fill", placeholder: "City", text: $city)

                    // STATE dropdown with placeholder + chevrons
                    HStack {
                        Image(systemName: "map.fill")
                            .foregroundColor(.gray)

                        Menu {
                            ForEach(usStates, id: \.self) { abbr in
                                Button(abbr) { state = abbr }
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Text(state.isEmpty ? "State" : state)
                                    .foregroundColor(state.isEmpty ? .secondary : .primary)
                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.footnote).foregroundColor(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(14)
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.gray.opacity(0.3), lineWidth: 1))

                    HStack {
                        Image(systemName: "mappin.and.ellipse")
                            .foregroundColor(.gray)
                        TextField("ZIP Code", text: $zipCode)
                            .keyboardType(.numberPad)
                            .onChange(of: zipCode) { _, newValue in
                                zipCode = newValue.filter { $0.isNumber } // keep digits only
                            }
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(14)
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.gray.opacity(0.3), lineWidth: 1))
                }

                SignupContinueButton(title: "Continue", isEnabled: isValid, action: onNext)

                SignupInfoCard(
                    icon: "lock.shield.fill",
                    title: "Your information is safe",
                    message: "Your address is only used for verification and is never shared with riders."
                )

                Spacer(minLength: 8)
            }
            .padding(.horizontal, 24)
            .padding(.top, 6)
        }
        .background(Color(.systemBackground))
        .hideKeyboardOnTap()
    }

    private func iconField(icon: String, placeholder: String, text: Binding<String>) -> some View {
        HStack {
            Image(systemName: icon).foregroundColor(.gray)
            TextField(placeholder, text: text)
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(14)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.gray.opacity(0.3), lineWidth: 1))
    }
}
