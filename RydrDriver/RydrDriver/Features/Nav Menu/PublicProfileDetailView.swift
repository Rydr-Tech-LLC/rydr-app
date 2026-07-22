//
//  PublicProfileDetailView.swift
//  RydrDriver
//
//  Created by Anthony Thomas La on 7/20/26.
//

import SwiftUI

struct PublicProfileDetailView: View {
    @ObservedObject var dashboardVM: DriverDashboardVM

    var body: some View {
        Group {
            if dashboardVM.isLoadingPublicProfile {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 20) {
                        photoSection
                        badgesSection
                        nameSection
                        ratingSection
                        rideTypesSection
                        vehicleSection
                        complimentsSection
                        errorSection
                    }
                    .padding()
                }
            }
        }
        .navigationTitle("Public Profile")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { dashboardVM.fetchPublicProfile() }
        .onAppear { dashboardVM.fetchPublicProfileIfNeeded() }
    }

    private var photoSection: some View {
        Group {
            if let approvedURL = dashboardVM.approvedProfilePhotoURL {
                AsyncImage(url: approvedURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    default:
                        profilePlaceholder
                    }
                }
                .frame(width: 120, height: 120)
                .clipShape(Circle())
                .overlay(Circle().stroke(Styles.rydrGradient, lineWidth: 3))
            } else {
                profilePlaceholder
            }
        }
    }

    private var profilePlaceholder: some View {
        Image(systemName: "person.circle.fill")
            .resizable()
            .frame(width: 120, height: 120)
            .foregroundStyle(Styles.rydrGradient)
    }

    private var badgesSection: some View {
        HStack(spacing: 12) {
            if dashboardVM.isDriverVerified {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(Styles.rydrGradient)
                    Text("Verified Driver")
                        .font(.caption.weight(.bold))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Styles.rydrGradient.opacity(0.12))
                .clipShape(Capsule())
            }
            if dashboardVM.isNewPhotoPending {
                HStack(spacing: 4) {
                    Image(systemName: "hourglass")
                        .foregroundStyle(.orange)
                    Text("Photo pending")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.orange)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.orange.opacity(0.12))
                .clipShape(Capsule())
            }
        }
    }

    private var nameSection: some View {
        Text(dashboardVM.riderFacingFirstName)
            .font(.title2.weight(.bold))
    }

    private var ratingSection: some View {
        HStack(spacing: 6) {
            Image(systemName: "star.fill")
                .foregroundStyle(Styles.rydrGradient)
            Text(String(format: "%.1f", dashboardVM.driverRating))
            if dashboardVM.isNewDriver {
                Text("• New driver")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var rideTypesSection: some View {
        Group {
            if !dashboardVM.approvedRideTypes.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(dashboardVM.approvedRideTypes, id: \.self) { type in
                            Text(type)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Styles.rydrGradient)
                                .clipShape(Capsule())
                        }
                    }
                }
            }
        }
    }

    private var vehicleSection: some View {
        Group {
            if let vehicle = dashboardVM.vehicle {
                VStack(alignment: .leading, spacing: 8) {
                    if let libraryURL = vehicle.libraryImageURL {
                        AsyncImage(url: libraryURL) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .scaledToFill()
                            default:
                                Color.gray.opacity(0.2)
                            }
                        }
                        .frame(height: 140)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    Text(vehicle.summaryText)
                        .font(.headline)
                    if let plate = dashboardVM.vehiclePlateText?.trimmingCharacters(in: .whitespacesAndNewlines), !plate.isEmpty {
                        Text(plate.uppercased())
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    } else {
                        Text("License plate unavailable")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding()
                .background(.regularMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 16))
            } else {
                Text("No vehicle info")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var complimentsSection: some View {
        Group {
            if !dashboardVM.compliments.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(dashboardVM.compliments, id: \.self) { compliment in
                            Text(compliment)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Styles.rydrGradient)
                                .clipShape(Capsule())
                        }
                    }
                }
            }
        }
    }

    private var errorSection: some View {
        Group {
            if let error = dashboardVM.publicProfileErrorMessage {
                VStack(spacing: 12) {
                    Text(error)
                        .foregroundStyle(.secondary)
                    Button("Retry") {
                        dashboardVM.fetchPublicProfile()
                    }
                    .tint(Styles.rydrGradient)
                }
            }
        }
    }
}
