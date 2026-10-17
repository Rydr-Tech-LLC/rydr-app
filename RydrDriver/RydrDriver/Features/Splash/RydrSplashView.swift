import SwiftUI

/// A native coin-spin entrance; no video playback, timers, or network dependencies.
struct RydrSplashView: View {
    let onFinished: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var arrived = false
    @State private var visible = false
    @State private var finished = false
    @State private var fadeOut = false

    var body: some View {
        GeometryReader { geometry in
            let size = min(geometry.size.width * 0.90, 380)
            ZStack {
                Color(colorScheme == .dark ? UIColor(red: 0.055, green: 0.025, blue: 0.04, alpha: 1) : .systemBackground)
                    .ignoresSafeArea()
                Circle().fill(Color.red.opacity(colorScheme == .dark ? 0.22 : 0.08))
                    .frame(width: size, height: size).blur(radius: 60)
                    .scaleEffect(arrived ? 1.12 : 0.5)
                ZStack {
                    // The original logos stay intact; an ivory face keeps the lettering legible in dark mode.
                    Circle().fill(Color(red: 1, green: 0.98, blue: 0.97).opacity(colorScheme == .dark ? 0.98 : 0))
                        .frame(width: size * 0.81, height: size * 0.81)
                    Image("RydrSplashLogo").resizable().scaledToFit().frame(width: size, height: size)
                }
                .shadow(color: .red.opacity(colorScheme == .dark ? 0.18 : 0.08), radius: 28, y: 12)
                .rotation3DEffect(.degrees(arrived || reduceMotion ? 0 : -540), axis: (x: 0.08, y: 1, z: 0), perspective: 0.65)
                .rotationEffect(.degrees(arrived || reduceMotion ? 0 : -16))
                .scaleEffect(arrived || reduceMotion ? 1 : 0.58)
                .offset(x: arrived || reduceMotion ? 0 : -geometry.size.width * 0.8)
                .opacity(visible ? 1 : 0)
                .accessibilityLabel("Rydr Driver logo")
                .accessibilityIdentifier("rydrSplashLogo")
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .opacity(fadeOut ? 0 : 1)
        .task {
            guard !finished else { return }
            do {
                withAnimation(.easeOut(duration: 0.2)) { visible = true }
                withAnimation(reduceMotion ? .easeOut(duration: 0.3) : .spring(response: 1.35, dampingFraction: 0.86)) { arrived = true }
                #if DEBUG && targetEnvironment(simulator)
                let duration = ProcessInfo.processInfo.arguments.contains("-RydrSplashUITest") ? 8.0 : (reduceMotion ? 0.65 : 1.9)
                #else
                let duration = reduceMotion ? 0.65 : 1.9
                #endif
                try await Task.sleep(for: .seconds(duration))
                withAnimation(.easeOut(duration: 0.25)) { fadeOut = true }
                try await Task.sleep(for: .seconds(0.25))
                guard !Task.isCancelled else { return }
                finished = true
                onFinished()
            } catch { /* A dismissed splash must never navigate later. */ }
        }
    }
}
