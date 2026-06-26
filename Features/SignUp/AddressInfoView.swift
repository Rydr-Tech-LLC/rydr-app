//
//  AddressEntryView.swift
//  RydrSignupFlow
//
import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import UIKit

struct AddressInfoView: View {
    @Binding var street: String
    @Binding var addressLine2: String
    @Binding var city: String
    @Binding var state: String
    @Binding var zipCode: String
    var onNext: () -> Void

    @Environment(\.dismiss) private var dismiss

    private let usStates = [
        "AL","AK","AZ","AR","CA","CO","CT","DE","FL","GA","HI","ID","IL","IN","IA",
        "KS","KY","LA","ME","MD","MA","MI","MN","MS","MO","MT","NE","NV","NH","NJ",
        "NM","NY","NC","ND","OH","OK","OR","PA","RI","SC","SD","TN","TX","UT","VT",
        "VA","WA","WV","WI","WY"
    ]

    private var canContinue: Bool {
        !street.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !city.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !state.isEmpty &&
        zipCode.filter(\.isNumber).count >= 5
    }

    var body: some View {
        SignupScreenScaffold(
            activeStep: 1,
            hero: {
                SignupMapPingHero()
            },
            content: {
                VStack(spacing: 18) {
                    Spacer(minLength: 184)

                    SignupFormPanel {
                        SignupStepHeader(active: 1)

                        VStack(spacing: 8) {
                            Text("Where Are You Located?")
                                .font(.system(size: 24, weight: .black, design: .rounded))
                                .foregroundStyle(SignupPalette.ink)
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                                .minimumScaleFactor(0.82)

                            Text("We'll use this to personalize your experience.")
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                .foregroundStyle(SignupPalette.muted)
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        VStack(spacing: 12) {
                        SignupInputRow(icon: "house", placeholder: "Street Address") {
                            TextField("Street Address", text: $street)
                                .textContentType(.streetAddressLine1)
                        }

                        SignupInputRow(icon: "number", placeholder: "Apt / Unit (optional)") {
                            TextField("Apt / Unit (optional)", text: $addressLine2)
                                .textContentType(.streetAddressLine2)
                        }

                        SignupInputRow(icon: "building.2", placeholder: "City") {
                            TextField("City", text: $city)
                                .textContentType(.addressCity)
                        }

                        HStack(spacing: 12) {
                            Image(systemName: "map")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(SignupPalette.red)
                                .frame(width: 18)

                            Menu {
                                ForEach(usStates, id: \.self) { abbr in
                                    Button(abbr) { state = abbr }
                                }
                            } label: {
                                HStack {
                                    Text(state.isEmpty ? "State" : state)
                                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                                        .foregroundStyle(state.isEmpty ? SignupPalette.muted.opacity(0.72) : SignupPalette.ink)
                                    Spacer()
                                    Image(systemName: "chevron.down")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundStyle(SignupPalette.red)
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .frame(height: 52)
                        .background(SignupPalette.field, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .stroke(SignupPalette.red.opacity(0.50), lineWidth: 1)
                        }
                        .shadow(color: Color.black.opacity(0.08), radius: 12, x: 0, y: 7)

                        SignupInputRow(icon: "mappin.and.ellipse", placeholder: "ZIP Code") {
                            TextField("ZIP Code", text: $zipCode)
                                .keyboardType(.numberPad)
                                .textContentType(.postalCode)
                                .onChange(of: zipCode) { _, newValue in
                                    zipCode = String(newValue.filter { $0.isNumber }.prefix(5))
                                }
                        }
                    }
                        .padding(.top, 2)

                        Button("Continue") { onNext() }
                            .buttonStyle(SignupPrimaryButtonStyle())
                            .disabled(!canContinue)
                            .opacity(canContinue ? 1 : 0.56)

                        SignupSecurityFooter(text: "Your address helps us match nearby rides faster.")
                    }
                }
            },
            onBack: { dismiss() }
        )
    }
}
