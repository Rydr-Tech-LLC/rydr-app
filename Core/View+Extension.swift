//
//  View+Extension.swift
//  RydrPlayground
//
//  Created by Khris Nunnally on 6/14/25.
//

import SwiftUI

extension View {
    func hideKeyboardOnTap() -> some View {
        self.simultaneousGesture(
            TapGesture().onEnded { _ in
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            }
        )
    }
}
extension View {
    func inputFieldStyle() -> some View {
        self
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(
                        LinearGradient(
                            colors: [Color.red, Color(red: 0.5, green: 0.0, blue: 0.13).opacity(0.7)],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        lineWidth: 1.5
                    )
            )
    }
}
