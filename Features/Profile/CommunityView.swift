//
//  CommunityView.swift
//  RydrPlayground
//

import SwiftUI

struct CommunityView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.openURL) private var openURL
    @StateObject private var viewModel = CommunityEventsViewModel()

    private let categories = CommunityEventCategory.allCases

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                header
                categoryScroller
                rydrAngleCard
                content
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 110)
        }
        .background(backgroundColor.ignoresSafeArea())
        .navigationTitle("Community")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.loadIfNeeded()
        }
        .refreshable {
            await viewModel.refresh()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 7) {
            Label("Atlanta, GA", systemImage: "mappin.and.ellipse")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Styles.rydrGradient)

            Text("Events in the city")
                .font(.system(size: 32, weight: .heavy, design: .rounded))
                .foregroundStyle(primaryText)

            Text("Find concerts, games, shows, and weekend plans. Ticket links open in Ticketmaster.")
                .font(.subheadline)
                .foregroundStyle(secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var categoryScroller: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(categories) { category in
                    Button {
                        Task { await viewModel.select(category) }
                    } label: {
                        HStack(spacing: 7) {
                            Image(systemName: category.icon)
                                .font(.caption.weight(.bold))
                            Text(category.title)
                                .font(.subheadline.weight(.bold))
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .foregroundStyle(viewModel.selectedCategory == category ? Color.white : primaryText)
                        .background(
                            Capsule()
                                .fill(viewModel.selectedCategory == category ? AnyShapeStyle(Styles.rydrGradient) : AnyShapeStyle(cardBackground))
                        )
                        .overlay(
                            Capsule()
                                .stroke(borderColor, lineWidth: viewModel.selectedCategory == category ? 0 : 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(category.title) events")
                    .accessibilityValue(viewModel.selectedCategory == category ? "Selected" : "Not selected")
                }
            }
            .padding(.vertical, 2)
        }
    }

    private var rydrAngleCard: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "car.fill")
                .font(.headline.weight(.bold))
                .foregroundStyle(Styles.rydrGradient)
                .frame(width: 38, height: 38)
                .background(Styles.rydrGradient.opacity(colorScheme == .dark ? 0.18 : 0.11), in: Circle())

            VStack(alignment: .leading, spacing: 5) {
                Text("Make a night of it")
                    .font(.headline.weight(.heavy))
                    .foregroundStyle(primaryText)

                Text("Buy tickets with Ticketmaster, then come back to Rydr when you're ready to book the ride there or home.")
                    .font(.subheadline)
                    .foregroundStyle(secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .background(angleCardBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Styles.rydrGradient.opacity(colorScheme == .dark ? 0.32 : 0.16), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading && viewModel.events.isEmpty {
            loadingState
        } else if let message = viewModel.errorMessage, viewModel.events.isEmpty {
            errorState(message)
        } else if viewModel.events.isEmpty {
            emptyState
        } else {
            LazyVStack(spacing: 14) {
                ForEach(viewModel.events) { event in
                    CommunityEventCard(event: event) {
                        openTicketmaster(event)
                    }
                }
            }
        }
    }

    private var loadingState: some View {
        VStack(spacing: 14) {
            ProgressView()
            Text("Loading Atlanta events")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(secondaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 42)
        .background(cardBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func errorState(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Events are unavailable", systemImage: "exclamationmark.triangle.fill")
                .font(.headline.weight(.bold))
                .foregroundStyle(primaryText)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(secondaryText)

            Button {
                Task { await viewModel.refresh() }
            } label: {
                Label("Try Again", systemImage: "arrow.clockwise")
                    .font(.subheadline.weight(.bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .foregroundStyle(.white)
                    .background(Styles.rydrGradient, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .background(cardBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "ticket")
                .font(.title2.weight(.bold))
                .foregroundStyle(Styles.rydrGradient)
            Text("No events found")
                .font(.headline.weight(.bold))
                .foregroundStyle(primaryText)
            Text("Try another category or check back soon.")
                .font(.subheadline)
                .foregroundStyle(secondaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 34)
        .background(cardBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func openTicketmaster(_ event: CommunityEvent) {
        guard let url = event.ticketURL else { return }
        openURL(url)
    }

    private var backgroundColor: Color {
        colorScheme == .dark ? .black : Color(.systemGroupedBackground)
    }

    private var cardBackground: Color {
        colorScheme == .dark ? Color(red: 0.085, green: 0.085, blue: 0.095) : .white
    }

    private var angleCardBackground: LinearGradient {
        LinearGradient(
            colors: colorScheme == .dark
                ? [Color(red: 0.13, green: 0.055, blue: 0.065), Color(red: 0.085, green: 0.085, blue: 0.095)]
                : [Color(red: 1.0, green: 0.93, blue: 0.94), .white],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var primaryText: Color {
        colorScheme == .dark ? .white : Color(red: 0.05, green: 0.08, blue: 0.14)
    }

    private var secondaryText: Color {
        colorScheme == .dark ? Color.white.opacity(0.66) : Color(red: 0.42, green: 0.43, blue: 0.50)
    }

    private var borderColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.08)
    }
}

private struct CommunityEventCard: View {
    @Environment(\.colorScheme) private var colorScheme
    let event: CommunityEvent
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 0) {
                eventImage

                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top, spacing: 12) {
                        dateBadge

                        VStack(alignment: .leading, spacing: 6) {
                            Text(event.title)
                                .font(.headline.weight(.heavy))
                                .foregroundStyle(primaryText)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)

                            Text(event.venueLine)
                                .font(.subheadline)
                                .foregroundStyle(secondaryText)
                                .lineLimit(2)
                        }
                    }

                    HStack(spacing: 10) {
                        Label(event.category, systemImage: "sparkles")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Styles.rydrGradient)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(Styles.rydrGradient.opacity(colorScheme == .dark ? 0.18 : 0.10), in: Capsule())

                        Spacer()

                        Label("Get Tickets", systemImage: "safari")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 13)
                            .padding(.vertical, 9)
                            .background(Styles.rydrGradient, in: Capsule())
                    }
                }
                .padding(14)
            }
            .background(cardBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(borderColor, lineWidth: 1)
            )
            .shadow(color: colorScheme == .dark ? .clear : Color.black.opacity(0.055), radius: 12, x: 0, y: 7)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(event.title), \(event.accessibilityDate), \(event.venueLine). Opens Ticketmaster.")
    }

    @ViewBuilder
    private var eventImage: some View {
        if let imageURL = event.imageURL {
            AsyncImage(url: imageURL) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                case .failure:
                    placeholderImage
                case .empty:
                    ZStack {
                        placeholderImage
                        ProgressView()
                            .tint(.white)
                    }
                @unknown default:
                    placeholderImage
                }
            }
            .frame(height: 154)
            .frame(maxWidth: .infinity)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        } else {
            placeholderImage
                .frame(height: 154)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }

    private var placeholderImage: some View {
        ZStack {
            Styles.rydrGradient
            Image(systemName: "ticket.fill")
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(.white)
        }
    }

    private var dateBadge: some View {
        VStack(spacing: 2) {
            Text(event.monthText)
                .font(.caption2.weight(.heavy))
                .foregroundStyle(Styles.rydrGradient)
            Text(event.dayText)
                .font(.title3.weight(.heavy))
                .foregroundStyle(primaryText)
        }
        .frame(width: 52, height: 54)
        .background(dateBadgeBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var cardBackground: Color {
        colorScheme == .dark ? Color(red: 0.085, green: 0.085, blue: 0.095) : .white
    }

    private var dateBadgeBackground: Color {
        colorScheme == .dark ? Color.white.opacity(0.07) : Color(red: 0.97, green: 0.97, blue: 0.98)
    }

    private var primaryText: Color {
        colorScheme == .dark ? .white : Color(red: 0.05, green: 0.08, blue: 0.14)
    }

    private var secondaryText: Color {
        colorScheme == .dark ? Color.white.opacity(0.66) : Color(red: 0.42, green: 0.43, blue: 0.50)
    }

    private var borderColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.10) : Color.black.opacity(0.07)
    }
}

@MainActor
private final class CommunityEventsViewModel: ObservableObject {
    @Published var selectedCategory: CommunityEventCategory = .featured
    @Published var events: [CommunityEvent] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let service = CommunityEventsService()
    private var hasLoaded = false

    func loadIfNeeded() async {
        guard !hasLoaded else { return }
        await refresh()
    }

    func select(_ category: CommunityEventCategory) async {
        guard selectedCategory != category else { return }
        selectedCategory = category
        await refresh()
    }

    func refresh() async {
        isLoading = true
        errorMessage = nil

        do {
            events = try await service.fetchEvents(category: selectedCategory)
            hasLoaded = true
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }
}

private struct CommunityEventsService {
    private var baseURL: URL {
        if let override = UserDefaults.standard.string(forKey: "communityBackendBaseURL"),
           let url = URL(string: override),
           !override.isEmpty {
            return url
        }

        if let value = Bundle.main.object(forInfoDictionaryKey: "RYDR_BACKEND_BASE_URL") as? String,
           let url = URL(string: value),
           !value.isEmpty {
            return url
        }

        return URL(string: "http://localhost:3000")!
    }

    func fetchEvents(category: CommunityEventCategory) async throws -> [CommunityEvent] {
        var components = URLComponents(url: baseURL.appendingPathComponent("events"), resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "category", value: category.apiValue),
            URLQueryItem(name: "city", value: "Atlanta"),
            URLQueryItem(name: "stateCode", value: "GA"),
            URLQueryItem(name: "size", value: "20")
        ]

        guard let url = components?.url else {
            throw CommunityEventsError.badURL
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 18

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw CommunityEventsError.badResponse
        }

        guard (200..<300).contains(http.statusCode) else {
            let serverError = try? JSONDecoder().decode(CommunityServerError.self, from: data)
            if let message = serverError?.message ?? serverError?.error {
                throw CommunityEventsError.server(message, url)
            }

            let body = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw CommunityEventsError.httpStatus(http.statusCode, body, url)
        }

        do {
            return try JSONDecoder().decode(CommunityEventsResponse.self, from: data).events
        } catch {
            throw CommunityEventsError.decoding
        }
    }
}

private enum CommunityEventsError: LocalizedError {
    case badURL
    case badResponse
    case decoding
    case httpStatus(Int, String?, URL)
    case server(String, URL)

    var errorDescription: String? {
        switch self {
        case .badURL:
            return "The events request could not be built."
        case .badResponse:
            return "The events service returned an unexpected response."
        case .decoding:
            return "The events service returned data Rydr could not read."
        case .httpStatus(let status, let body, let url):
            if let body, !body.isEmpty {
                return "Events request failed with HTTP \(status): \(body) (\(url.host ?? "backend"))"
            }
            return "Events request failed with HTTP \(status) from \(url.host ?? "backend")."
        case .server(let message, let url):
            return "\(message) (\(url.host ?? "backend"))"
        }
    }
}

private struct CommunityEventsResponse: Decodable {
    let events: [CommunityEvent]
}

private struct CommunityServerError: Decodable {
    let error: String?
    let message: String?
}

private struct CommunityEvent: Identifiable, Decodable {
    let id: String
    let title: String
    let category: String
    let genre: String?
    let dateText: String?
    let localDate: String?
    let localTime: String?
    let venueName: String
    let city: String
    let state: String
    let address: String?
    let latitude: Double?
    let longitude: Double?
    let imageURL: URL?
    let ticketURL: URL?
    let price: CommunityEventPrice?

    var venueLine: String {
        "\(venueName) • \(city), \(state)"
    }

    var monthText: String {
        guard let date = parsedDate else { return "TBA" }
        return Self.monthFormatter.string(from: date).uppercased()
    }

    var dayText: String {
        guard let date = parsedDate else { return "--" }
        return Self.dayFormatter.string(from: date)
    }

    var accessibilityDate: String {
        guard let date = parsedDate else { return dateText ?? "date to be announced" }
        return Self.accessibilityDateFormatter.string(from: date)
    }

    private var parsedDate: Date? {
        guard let localDate else { return nil }
        return Self.ticketmasterDateFormatter.date(from: localDate)
    }

    private static let ticketmasterDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static let monthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMM"
        return formatter
    }()

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "d"
        return formatter
    }()

    private static let accessibilityDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        formatter.timeStyle = .none
        return formatter
    }()
}

private struct CommunityEventPrice: Decodable {
    let min: Double?
    let max: Double?
    let currency: String?
}

private enum CommunityEventCategory: String, CaseIterable, Identifiable {
    case featured
    case music
    case sports
    case arts
    case comedy
    case family
    case festivals

    var id: String { rawValue }

    var title: String {
        switch self {
        case .featured: return "Featured"
        case .music: return "Music"
        case .sports: return "Sports"
        case .arts: return "Arts"
        case .comedy: return "Comedy"
        case .family: return "Family"
        case .festivals: return "Festivals"
        }
    }

    var apiValue: String { rawValue }

    var icon: String {
        switch self {
        case .featured: return "star.fill"
        case .music: return "music.note"
        case .sports: return "sportscourt.fill"
        case .arts: return "theatermasks.fill"
        case .comedy: return "face.smiling"
        case .family: return "figure.2.and.child.holdinghands"
        case .festivals: return "sparkles"
        }
    }
}
