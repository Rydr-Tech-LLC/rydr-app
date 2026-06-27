//
//  DriverOnboardingStepIndicator.swift
//  Rydr Driver
//
//  Reusable "flow bubble" progress tracker used across every driver signup /
//  onboarding screen (name entry through payouts). Shows a row of circular
//  bubbles connected by lines: completed steps render as a filled gradient
//  circle with a checkmark, the current step renders as a hollow gradient
//  ring, and future steps render as a small gray dot. A "Step X of N" caption
//  sits above the bubble row.
//

import SwiftUI

struct DriverOnboardingStepIndicator: View {
    /// 1-based index of the step currently being shown.
    let currentStep: Int
    /// Total number of steps in the flow.
    let totalSteps: Int
    /// Optional title shown under the "Step X of N" caption, e.g. "Identity Verification".
    var stepTitle: String? = nil

    var body: some View {
        VStack(spacing: 8) {
            Text("Step \(currentStep) of \(totalSteps)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            if let stepTitle {
                Text(stepTitle)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.secondary.opacity(0.8))
            }

            HStack(spacing: 0) {
                ForEach(1...max(totalSteps, 1), id: \.self) { step in
                    bubble(for: step)
                    if step != totalSteps {
                        connectorLine(filled: step < currentStep)
                    }
                }
            }
            .animation(.spring(response: 0.45, dampingFraction: 0.85), value: currentStep)
        }
        .padding(.horizontal, 4)
        .padding(.top, 4)
    }

    @ViewBuilder
    private func bubble(for step: Int) -> some View {
        ZStack {
            if step < currentStep {
                Circle()
                    .fill(Styles.rydrGradient)
                    .frame(width: 22, height: 22)
                    .shadow(color: .red.opacity(0.25), radius: 4, y: 2)
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white)
            } else if step == currentStep {
                Circle()
                    .fill(Color(.systemBackground))
                    .frame(width: 22, height: 22)
                Circle()
                    .strokeBorder(Styles.rydrGradient, lineWidth: 2.5)
                    .frame(width: 22, height: 22)
                Circle()
                    .fill(Styles.rydrGradient)
                    .frame(width: 7, height: 7)
            } else {
                Circle()
                    .fill(Color(.systemGray4))
                    .frame(width: 8, height: 8)
            }
        }
        .frame(width: 22, height: 22)
        .accessibilityHidden(true)
    }

    private func connectorLine(filled: Bool) -> some View {
        Rectangle()
            .fill(filled ? AnyShapeStyle(Styles.rydrGradient) : AnyShapeStyle(Color(.systemGray5)))
            .frame(height: 3)
            .frame(maxWidth: .infinity)
    }
}

#Preview {
    VStack(spacing: 30) {
        DriverOnboardingStepIndicator(currentStep: 1, totalSteps: 8, stepTitle: "Your Details")
        DriverOnboardingStepIndicator(currentStep: 6, totalSteps: 8, stepTitle: "Identity Verification")
        DriverOnboardingStepIndicator(currentStep: 8, totalSteps: 8, stepTitle: "Payouts")
    }
    .padding()
}
