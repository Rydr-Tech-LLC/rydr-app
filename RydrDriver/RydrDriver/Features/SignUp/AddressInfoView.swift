//
//  AddressEntryView.swift
//  RydrSignupFlow
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
    var onNext: () -> Void

    private let usStates = [
        "AL","AK","AZ","AR","CA","CO","CT","DE","FL","GA","HI","ID","IL","IN","IA",
        "KS","KY","LA","ME","MD","MA","MI","MN","MS","MO","MT","NE","NV","NH","NJ",
        "NM","NY","NC","ND","OH","OK","OR","PA","RI","SC","SD","TN","TX","UT","VT",
        "VA","WA","WV","WI","WY"
    ]

    var body: some View {
        VStack(spacing: 25) {
            Text("Where Are You Located?")
                .font(.title)
                .fontWeight(.bold)
                .foregroundStyle(
                    LinearGradient(colors: [Color.red, Color(red: 0.5, green: 0.0, blue: 0.13).opacity(0.7)],
                                   startPoint: .leading, endPoint: .trailing)
                )

            Group {
                HStack {
                    Image(systemName: "house")
                        .foregroundColor(.gray)
                    TextField("Street Address", text: $street)
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(10)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                )

                HStack {
                    Image(systemName: "number")
                        .foregroundColor(.gray)
                    TextField("Apt / Unit (optional)", text: $addressLine2)
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(10)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                )

                HStack {
                    Image(systemName: "building.2")
                        .foregroundColor(.gray)
                    TextField("City", text: $city)
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(10)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                )

                // STATE dropdown with placeholder + chevrons
                HStack {
                    Image(systemName: "map")
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
                .cornerRadius(10)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                )

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
                .cornerRadius(10)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                )
            }

            Button("Continue") { onNext() }
                .buttonStyle(.borderedProminent)
                .tint(.red)
        }
        .padding(.horizontal)
    }
}
