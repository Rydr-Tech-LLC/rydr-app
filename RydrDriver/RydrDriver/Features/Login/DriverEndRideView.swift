//
//  DriverEndRideView.swift
//  RydrDriver
//
//  Optional rider rating after a driver completes a ride.
//

import SwiftUI

struct DriverEndRideView: View {
    let ride: DriverActiveRide
    let onClose: () -> Void
    let onSubmit: (_ rating: Int?, _ feedback: String) -> Void

    @State private var rating: Int?
    @State private var feedback = ""

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Rate \(ride.riderName)")
                        .font(.title2.weight(.black))
                    Text("Rating is optional. Add feedback only if it helps the next trip.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 10) {
                    ForEach(1...5, id: \.self) { value in
                        Button {
                            rating = value
                        } label: {
                            Image(systemName: (rating ?? 0) >= value ? "star.fill" : "star")
                                .font(.system(size: 30, weight: .bold))
                                .foregroundStyle((rating ?? 0) >= value ? Color.yellow : Color(.systemGray3))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)

                TextEditor(text: $feedback)
                    .frame(minHeight: 120)
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 14).fill(Color(.secondarySystemBackground)))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.black.opacity(0.06), lineWidth: 1))

                Button {
                    onSubmit(rating, feedback)
                } label: {
                    Text(rating == nil && feedback.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Skip Rating" : "Submit Rating")
                        .font(.headline.weight(.bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(RoundedRectangle(cornerRadius: 14).fill(Styles.rydrGradient))
                        .foregroundStyle(.white)
                }

                Spacer()
            }
            .padding()
            .navigationTitle("Ride Complete")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        onClose()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.headline.weight(.bold))
                    }
                    .accessibilityLabel("Close rating")
                }
            }
        }
    }
}
