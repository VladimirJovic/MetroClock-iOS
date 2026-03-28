import SwiftUI
import Combine

// MARK: - FlipDigit
/// Single animated digit card for the flip clock.
struct FlipDigit: View {
    let digit: Int
    @State private var scaleY: CGFloat = 1.0

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.mcSurface)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(Color.mcBorder, lineWidth: 1)
                )

            Text("\(digit)")
                .font(.system(size: 64, weight: .bold, design: .monospaced))
                .foregroundStyle(Color.mcOrange)
                .scaleEffect(y: scaleY)

            // Centre divider
            Rectangle()
                .fill(Color.black.opacity(0.7))
                .frame(height: 1)
        }
        .frame(width: 74, height: 90)
        .onChange(of: digit) { _, _ in
            withAnimation(.easeIn(duration: 0.15)) { scaleY = 0.03 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                withAnimation(.easeOut(duration: 0.15)) { scaleY = 1.0 }
            }
        }
    }
}

// MARK: - FlipClockView
/// Four-digit (HH:mm) flip clock that updates every second.
struct FlipClockView: View {
    @State private var h1 = 0
    @State private var h2 = 0
    @State private var m1 = 0
    @State private var m2 = 0
    @State private var colonVisible = true

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: 6) {
            FlipDigit(digit: h1)
            FlipDigit(digit: h2)

            Text(":")
                .font(.system(size: 64, weight: .bold, design: .monospaced))
                .foregroundStyle(Color.mcOrange)
                .opacity(colonVisible ? 1 : 0.15)
                .padding(.bottom, 8)

            FlipDigit(digit: m1)
            FlipDigit(digit: m2)
        }
        .onAppear { updateDigits() }
        .onReceive(timer) { _ in
            updateDigits()
            withAnimation(.easeInOut(duration: 0.25)) {
                colonVisible.toggle()
            }
        }
    }

    private func updateDigits() {
        let now = Calendar.current.dateComponents([.hour, .minute], from: Date())
        let hour = (now.hour ?? 0) % 12
        let h12  = hour == 0 ? 12 : hour
        let min  = now.minute ?? 0
        h1 = h12 / 10
        h2 = h12 % 10
        m1 = min / 10
        m2 = min % 10
    }
}

// MARK: - HolographicButton
/// Holographic rotating-ring clock-in / clock-out button.
struct HolographicButton: View {
    let isClockedIn: Bool
    let isEnabled: Bool
    let isLoading: Bool
    let action: () -> Void

    @State private var rotation: Double   = 0
    @State private var glowRadius: CGFloat = 20

    private let gradientColors: [Color] = [
        Color(hex: "EA4500"), Color(hex: "FF7030"),
        Color(hex: "FFB347"), Color(hex: "FF4500"),
        Color(hex: "C13A00"), Color(hex: "6B1E00"),
        Color(hex: "EA4500")
    ]

    var body: some View {
        Button(action: action) {
            ZStack {
                // Outer rotating gradient ring
                Circle()
                    .fill(
                        AngularGradient(
                            colors: gradientColors,
                            center: .center
                        )
                    )
                    .blur(radius: 1)
                    .rotationEffect(.degrees(rotation))

                // Inner dark core
                Circle()
                    .fill(Color.mcBackground)
                    .padding(4)

                // Label
                if isLoading {
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(1.4)
                } else {
                    VStack(spacing: 4) {
                        Text(isClockedIn ? "Clock Out" : "Clock In")
                            .font(.system(size: 14, weight: .bold))
                            .tracking(3.5)
                            .textCase(.uppercase)
                            .foregroundStyle(Color.mcText)

                        Text(isClockedIn ? "Tap to stop" : "Tap to start")
                            .font(.system(size: 9, weight: .medium))
                            .tracking(2.4)
                            .textCase(.uppercase)
                            .foregroundStyle(Color.mcTextTertiary)
                    }
                }
            }
            .frame(width: 176, height: 176)
            .shadow(color: Color.mcOrange.opacity(glowRadius == 20 ? 0.22 : 0.45), radius: glowRadius)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled || isLoading)
        .opacity(isEnabled ? 1 : 0.38)
        .onAppear {
            withAnimation(.linear(duration: 4).repeatForever(autoreverses: false)) {
                rotation = 360
            }
            withAnimation(.easeInOut(duration: 2.5).repeatForever(autoreverses: true)) {
                glowRadius = 50
            }
        }
    }
}

// MARK: - StatusChip
/// Pill chip showing clocked-in / clocked-out state.
struct StatusChip: View {
    let isClockedIn: Bool
    @State private var dotOpacity: Double = 1.0

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(isClockedIn ? Color.white.opacity(0.6) : Color.mcOrange)
                .frame(width: 5, height: 5)
                .opacity(dotOpacity)

            Text(isClockedIn ? "Clocked In" : "Clocked Out")
                .font(.system(size: 10, weight: .semibold))
                .tracking(2.0)
                .textCase(.uppercase)
                .foregroundStyle(isClockedIn ? Color.white.opacity(0.7) : Color.mcOrange.opacity(0.9))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color.mcSurface)
        .clipShape(Capsule())
        .overlay(
            Capsule().strokeBorder(Color(hex: "191922"), lineWidth: 1)
        )
        .onAppear { animateDot() }
        .onChange(of: isClockedIn) { _, _ in animateDot() }
    }

    private func animateDot() {
        dotOpacity = 1.0
        guard !isClockedIn else { return }
        withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
            dotOpacity = 0.35
        }
    }
}

// MARK: - LocationIndicator
/// Small location / wifi status row.
struct LocationIndicator: View {
    let text: String

    var body: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(Color.mcTextFaint)
                .frame(width: 4, height: 4)

            Text(text)
                .font(.system(size: 11, weight: .regular))
                .tracking(1.4)
                .textCase(.uppercase)
                .foregroundStyle(Color.mcTextFaint)
        }
    }
}

// MARK: - MCCard
/// Reusable dark surface card with hairline border.
struct MCCard<Content: View>: View {
    let content: () -> Content

    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    var body: some View {
        content()
            .background(Color.mcSurface)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(Color.mcBorder, lineWidth: 1)
            )
    }
}
