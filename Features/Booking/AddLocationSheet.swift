//
//  AddLocationSheet.swift
//  RydrPlayground
//
//  Created by Khris Nunnally on 8/23/25.
//


// AddLocationSheet.swift
import SwiftUI
import MapKit
import UIKit

public struct AddLocationSheet: View {
    public enum Shortcut: String, CaseIterable { case home, work, custom
        var icon: String { switch self { case .home: "house.fill"; case .work: "briefcase.fill"; case .custom: "star.fill" } }
        var title: String { rawValue.capitalized }
    }

    public var onSave: ((Shortcut, MKMapItem) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var selected: Shortcut = .home
    @State private var searchText = ""
    @FocusState private var searching: Bool
    @StateObject private var completer = SearchCompleter()

    public init(onSave: ((Shortcut, MKMapItem) -> Void)? = nil) {
        self.onSave = onSave
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                ShortcutPicker(selected: $selected) { searching = true }

                SearchField(text: $searchText)
                    .focused($searching)
                    .onChange(of: searchText) { _, newValue in
                        completer.setQuery(newValue)
                    }

                if !completer.results.isEmpty {
                    SuggestionList(results: completer.results) { completion in
                        let req = MKLocalSearch.Request(completion: completion)
                        MKLocalSearch(request: req).start { resp, _ in
                            guard let item = resp?.mapItems.first else { return }
                            onSave?(selected, item)
                            dismiss()
                        }
                    }
                }

                Spacer(minLength: 0)
            }
            .padding()
            .background(
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        dismissKeyboard()
                    }
            )
            .navigationTitle("Add Location")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        dismissKeyboard()
                    }
                }
            }
        }
    }

    private func dismissKeyboard() {
        searching = false
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

// MARK: - Private UI used only by the sheet

private struct ShortcutPicker: View {
    @Binding var selected: AddLocationSheet.Shortcut
    var onPick: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            ForEach(AddLocationSheet.Shortcut.allCases, id: \.self) { kind in
                Button {
                    selected = kind; onPick()
                } label: {
                    VStack(spacing: 8) {
                        Image(systemName: kind.icon)
                            .font(.system(size: 22, weight: .semibold))
                            .frame(width: 48, height: 48)
                            .background(
                                LinearGradient(
                                    colors: [Color(red: 1, green: 0.27, blue: 0.27),
                                             Color(red: 1, green: 0.42, blue: 0.24)],
                                    startPoint: .topLeading, endPoint: .bottomTrailing
                                )
                            )
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        Text(kind.title).font(.footnote)
                    }
                    .padding(6)
                }
            }
        }
    }
}

private struct SearchField: View {
    @Binding var text: String
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search for a place", text: $text)
                .textInputAutocapitalization(.words)
                .disableAutocorrection(true)
                .submitLabel(.search)
        }
        .padding(12)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct SuggestionList: View {
    let results: [MKLocalSearchCompletion]
    var onSelect: (MKLocalSearchCompletion) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ForEach(results, id: \.self) { r in
                Button { onSelect(r) } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(r.title).font(.subheadline)
                        if !r.subtitle.isEmpty { Text(r.subtitle).font(.caption).foregroundStyle(.secondary) }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading).padding(12)
                }
                Divider()
            }
        }
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.black.opacity(0.06), lineWidth: 1))
    }
}
