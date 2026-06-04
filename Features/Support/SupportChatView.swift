//
//  SupportChatView.swift
//  RydrPlayground
//
//  Ticket-based support chat. Support replies can be added manually in Firestore for now.
//

import SwiftUI
import FirebaseFirestore

struct SupportChatView: View {
    let ticketId: String
    var subject: String = "Support chat"

    @Environment(\.dismiss) private var dismiss
    @State private var messages: [SupportMessage] = []
    @State private var draftText = ""
    @State private var errorMessage: String?
    @State private var isLoading = true
    @State private var isSending = false
    @State private var listener: ListenerRegistration?
    @State private var setupTask: Task<Void, Never>?

    private let service = SupportTicketService()

    var body: some View {
        VStack(spacing: 0) {
            notice
            messageList

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    .background(Color(.secondarySystemGroupedBackground))
            }

            Divider()
            inputBar
        }
        .navigationTitle(subject)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") { dismiss() }
            }
        }
        .onAppear(perform: startListening)
        .onDisappear(perform: stopListening)
    }

    private var notice: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "person.crop.circle.badge.questionmark")
                .foregroundStyle(Styles.rydrGradient)
            Text("A Rydr support specialist will reply as soon as possible.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 10) {
                    if isLoading {
                        ProgressView("Loading messages...")
                            .padding(.top, 32)
                    } else if messages.isEmpty {
                        ContentUnavailableView(
                            "No messages yet",
                            systemImage: "bubble.left.and.bubble.right",
                            description: Text("Send a message to start the support conversation.")
                        )
                        .padding(.top, 48)
                    } else {
                        ForEach(messages) { message in
                            messageRow(message)
                                .id(message.id)
                        }
                    }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .onChange(of: messages.count, initial: false) { _, _ in
                scrollToLatest(using: proxy)
            }
        }
    }

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField("Message support", text: $draftText, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...4)

            Button(action: sendMessage) {
                Image(systemName: "paperplane.fill")
                    .font(.headline.weight(.semibold))
                    .frame(width: 42, height: 38)
            }
            .foregroundStyle(canSend ? Color.red : Color.secondary)
            .disabled(!canSend)
            .accessibilityLabel("Send message")
        }
        .padding()
        .background(Color(.systemBackground))
    }

    private var canSend: Bool {
        !draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSending
    }

    private func messageRow(_ message: SupportMessage) -> some View {
        let isRiderMessage = message.senderRole == "rider"

        return HStack {
            if isRiderMessage {
                Spacer(minLength: 52)
            }

            Text(message.text)
                .font(.body)
                .foregroundStyle(isRiderMessage ? Color.white : Color.primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(isRiderMessage ? Color.red : Color(.systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(isRiderMessage ? Color.clear : Color.black.opacity(0.06), lineWidth: 1)
                )

            if !isRiderMessage {
                Spacer(minLength: 52)
            }
        }
    }

    private func startListening() {
        guard setupTask == nil, listener == nil else { return }
        isLoading = true

        setupTask = Task {
            do {
                let registration = try await service.listenToTicketMessages(ticketId: ticketId) { result in
                    Task { @MainActor in
                        switch result {
                        case .success(let newMessages):
                            messages = newMessages
                            isLoading = false
                            errorMessage = nil
                        case .failure(let error):
                            isLoading = false
                            errorMessage = error.localizedDescription
                        }
                    }
                }
                guard !Task.isCancelled else {
                    registration.remove()
                    return
                }
                await MainActor.run {
                    listener = registration
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    isLoading = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func stopListening() {
        setupTask?.cancel()
        setupTask = nil
        listener?.remove()
        listener = nil
    }

    private func sendMessage() {
        let text = draftText
        draftText = ""
        isSending = true
        errorMessage = nil

        Task {
            do {
                try await service.sendMessage(ticketId: ticketId, text: text)
                await MainActor.run {
                    isSending = false
                }
            } catch {
                await MainActor.run {
                    draftText = text
                    isSending = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func scrollToLatest(using proxy: ScrollViewProxy) {
        guard let lastMessage = messages.last else { return }
        DispatchQueue.main.async {
            withAnimation(.easeOut(duration: 0.2)) {
                proxy.scrollTo(lastMessage.id, anchor: .bottom)
            }
        }
    }
}
