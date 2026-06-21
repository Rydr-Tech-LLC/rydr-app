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
        ZStack {
            SignupPalette.background.ignoresSafeArea()
            LocationHero()
                .frame(height: 290)
                .frame(maxHeight: .infinity, alignment: .top)
                .ignoresSafeArea(edges: .top)
                .accessibilityHidden(true)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 17) {
                    SignupBackButton { dismiss() }

                    Spacer(minLength: 82)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Where Are")
                            .foregroundStyle(SignupPalette.ink)
                        HStack(spacing: 7) {
                            Text("You")
                                .foregroundStyle(SignupPalette.ink)
                            Text("Located?")
                                .foregroundStyle(SignupPalette.red)
                        }
                    }
                    .font(.system(size: 29, weight: .black, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.76)

                    Text("This helps us find rides\nnear you.")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(SignupPalette.muted)

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
                        .padding(.top, 8)

                    SignupProgressDots(active: 1)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 6)
                }
                .padding(.horizontal, 28)
                .padding(.top, 16)
                .padding(.bottom, 28)
                .frame(maxWidth: 440)
                .frame(maxWidth: .infinity)
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
    }
}

private struct LocationHero: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    SignupPalette.background,
                    Color(red: 1, green: 0.90, blue: 0.93).opacity(0.38),
                    SignupPalette.background.opacity(0.90)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            RoadGrid()
                .stroke(SignupPalette.muted.opacity(0.16), lineWidth: 1)
                .offset(y: 20)
            SignupSpeedLines()
                .stroke(
                    LinearGradient(
                        colors: [SignupPalette.red.opacity(0), SignupPalette.red.opacity(0.62), SignupPalette.red.opacity(0)],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    style: StrokeStyle(lineWidth: 4, lineCap: .round)
                )
                .offset(y: 74)
                .blur(radius: 0.4)
            SignupMiniCity()
                .fill(SignupPalette.red.opacity(0.13))
                .frame(width: 150, height: 110)
                .offset(x: 105, y: 42)
            Image(systemName: "mappin.circle.fill")
                .font(.system(size: 82, weight: .black))
                .foregroundStyle(SignupPalette.red)
                .shadow(color: SignupPalette.red.opacity(0.36), radius: 20, x: 0, y: 12)
                .offset(x: 18, y: 18)
        }
    }
}

private struct RoadGrid: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        for index in 0..<12 {
            let x = rect.width * CGFloat(index) / 11
            path.move(to: CGPoint(x: x, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.midX + (x - rect.midX) * 1.8, y: rect.maxY))
        }
        for index in 0..<10 {
            let y = rect.height * CGFloat(index) / 9
            path.move(to: CGPoint(x: rect.minX, y: y))
            path.addLine(to: CGPoint(x: rect.maxX, y: y))
        }
        return path
    }
}
