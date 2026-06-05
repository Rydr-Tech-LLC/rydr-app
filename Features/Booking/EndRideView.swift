//
//  EndRideView.swift
//  RydrPlayground
//
//  Created by Khris Nunnally on 8/29/25.
//
import SwiftUI

struct EndRideView: View {
    let ride: Receipt?
    let onDone: () -> Void
    var onTipSelected: (Int) -> Void = { _ in }

    @State private var rating: Int = 0
    @State private var selectedCompliments: Set<String> = []
    @State private var selectedTip: Int = 0     // cents
    @State private var extraNotes: String = ""

    private let complimentSet = [
        "Clean Car","Friendly","Great Service","Excellent Navigation",
        "Smooth Driving","Great Conversation"
    ]
    private let tipOptions: [Int] = [0, 200, 500, 1000]   // $0, $2, $5, $10

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    headerSection
                    starsSection
                    complimentsSection
                    tipSection
                    receiptSection
                    notesSection
                    submitSection
                }
                .padding()
            }
            .navigationTitle("Rate your ride")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { finishRide() }
                }
            }
        }
    }

    // MARK: - Sections (small views = fast type-check)

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Trip complete")
                .font(.headline)
            if let r = ride {
                Text("\(r.pickup) → \(r.dropoff)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var starsSection: some View {
        HStack(spacing: 10) {
            ForEach(1...5, id: \.self) { i in
                Button {
                    rating = i
                } label: {
                    Image(systemName: i <= rating ? "star.fill" : "star")
                        .font(.title)
                        .foregroundStyle(.red)   // keep simple & readable
                }
                .buttonStyle(.plain)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Rating")
        .accessibilityValue("\(rating) stars")
    }

    private var complimentsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Compliments").font(.headline)

            // lightweight pill grid
            let cols = [GridItem(.adaptive(minimum: 140), spacing: 10)]
            LazyVGrid(columns: cols, spacing: 10) {
                ForEach(complimentSet, id: \.self) { c in
                    let isOn = selectedCompliments.contains(c)
                    Button {
                        if isOn { selectedCompliments.remove(c) }
                        else    { selectedCompliments.insert(c) }
                    } label: {
                        Text(c)
                            .font(.footnote)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .background(RoundedRectangle(cornerRadius: 10).fill(isOn ? Color.red.opacity(0.12) : Color(.systemGray6)))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(isOn ? Color.red : Color.clear, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var tipSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Tip").font(.headline)
            HStack(spacing: 10) {
                ForEach(tipOptions, id: \.self) { cents in
                    let isOn = selectedTip == cents
                    Button {
                        selectedTip = cents
                    } label: {
                        Text(cents == 0 ? "No tip" : "$\(cents/100)")
                            .font(.footnote.weight(.semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(RoundedRectangle(cornerRadius: 10).fill(isOn ? Color.red.opacity(0.12) : Color(.systemGray6)))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(isOn ? Color.red : Color.clear, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private var receiptSection: some View {
        if let displayReceipt {
            VStack(alignment: .leading, spacing: 12) {
                Text("Receipt").font(.headline)

                receiptRow("Driver", displayReceipt.driverName)
                receiptRow("When", displayReceipt.date.formatted(date: .abbreviated, time: .shortened))
                receiptRow("Route", displayReceipt.pickup + " → " + displayReceipt.dropoff, lineLimit: 1)
                receiptRow(
                    "Distance / Time",
                    "\(String(format: "%.1f", displayReceipt.distanceMiles)) mi • \(Int(displayReceipt.durationMinutes)) min"
                )

                Divider()

                receiptAmountRow("Total", displayReceipt.fare, isTotal: true)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Charge breakdown")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)

                    ForEach(displayReceipt.chargeBreakdown.lineItems) { item in
                        receiptAmountRow(item.title, item.amount)
                    }
                }

                Divider()

                receiptRow("Paid with", displayReceipt.cardMasked)
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 16).fill(.ultraThinMaterial))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.black.opacity(0.06), lineWidth: 1))
        }
    }

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Anything to add?").font(.headline)
            TextEditor(text: $extraNotes)
                .frame(minHeight: 90)
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color(.systemGray6)))
        }
    }

    private var submitSection: some View {
        Button {
            finishRide()
        } label: {
            Text("Submit").frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .padding(.top, 4)
    }

    private var displayReceipt: Receipt? {
        ride?.addingTip(cents: selectedTip)
    }

    private func finishRide() {
        onTipSelected(selectedTip)
        onDone()
    }

    private func receiptRow(_ title: String, _ value: String, lineLimit: Int? = nil) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.primary)
            Spacer(minLength: 12)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .multilineTextAlignment(.trailing)
                .lineLimit(lineLimit)
                .foregroundStyle(Styles.rydrGradient)
        }
    }

    private func receiptAmountRow(_ title: String, _ amount: Double, isTotal: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
                .font(isTotal ? .headline : .subheadline)
                .fontWeight(isTotal ? .bold : .regular)
                .foregroundStyle(.primary)
            Spacer(minLength: 12)
            Text(currency(amount))
                .font(isTotal ? .headline.bold() : .subheadline.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(Styles.rydrGradient)
        }
    }

    private func currency(_ amount: Double) -> String {
        let sign = amount < 0 ? "-$" : "$"
        return sign + String(format: "%.2f", abs(amount))
    }
}

