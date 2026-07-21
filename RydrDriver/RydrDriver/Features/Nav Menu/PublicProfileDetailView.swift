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
        ScrollView {
            VStack(spacing: 20) {
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

                Text(dashboardVM.riderFacingFirstName)
                    .font(.title2.weight(.bold))

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
                        Text("License plate displayed after ride match")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                    .background(.regularMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                } else {
                    Text("No vehicle info")
                        .foregroundStyle(.secondary)
                }

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

                if let error = dashboardVM.errorMessage {
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
            .padding()
        }
        .navigationTitle("Public Profile")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { dashboardVM.fetchPublicProfile() }
        .onAppear { dashboardVM.fetchPublicProfileIfNeeded() }
    }

    private var profilePlaceholder: some View {
        Image(systemName: "person.circle.fill")
            .resizable()
            .frame(width: 120, height: 120)
            .foregroundStyle(Styles.rydrGradient)
    }
}
