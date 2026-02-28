import SwiftUI

struct LiquidGlassBackground: View {
    @State private var animating = false

    // 3x3 grid = 9 control points
    private var points: [SIMD2<Float>] {
        if animating {
            return [
                SIMD2(0.0, 0.0), SIMD2(0.55, -0.05), SIMD2(1.0, 0.0),
                SIMD2(-0.05, 0.55), SIMD2(0.45, 0.55), SIMD2(1.05, 0.45),
                SIMD2(0.0, 1.0), SIMD2(0.45, 1.05), SIMD2(1.0, 1.0),
            ]
        } else {
            return [
                SIMD2(0.0, 0.0), SIMD2(0.45, 0.05), SIMD2(1.0, 0.0),
                SIMD2(0.05, 0.45), SIMD2(0.55, 0.45), SIMD2(0.95, 0.55),
                SIMD2(0.0, 1.0), SIMD2(0.55, 0.95), SIMD2(1.0, 1.0),
            ]
        }
    }

    private let colors: [Color] = [
        Color(red: 0.15, green: 0.15, blue: 0.25),
        Color(red: 0.18, green: 0.16, blue: 0.30),
        Color(red: 0.14, green: 0.18, blue: 0.28),
        Color(red: 0.16, green: 0.20, blue: 0.32),
        Color(red: 0.20, green: 0.18, blue: 0.35),
        Color(red: 0.15, green: 0.22, blue: 0.30),
        Color(red: 0.12, green: 0.14, blue: 0.22),
        Color(red: 0.18, green: 0.15, blue: 0.28),
        Color(red: 0.14, green: 0.16, blue: 0.24),
    ]

    var body: some View {
        MeshGradient(
            width: 3,
            height: 3,
            points: points,
            colors: colors
        )
        .blur(radius: 40)
        .opacity(0.3)
        .ignoresSafeArea()
        .onAppear {
            withAnimation(.easeInOut(duration: 3).repeatForever(autoreverses: true)) {
                animating = true
            }
        }
    }
}

// MARK: - Recording Pulse Indicator

struct RecordingPulseIndicator: View {
    let isRecording: Bool

    @State private var pulse = false

    var body: some View {
        Circle()
            .fill(.red)
            .frame(width: 12, height: 12)
            .scaleEffect(pulse ? 1.3 : 1.0)
            .opacity(pulse ? 0.6 : 1.0)
            .shadow(color: .red.opacity(0.5), radius: pulse ? 8 : 2)
            .onChange(of: isRecording) { _, recording in
                if recording {
                    withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                        pulse = true
                    }
                } else {
                    withAnimation(.easeOut(duration: 0.3)) {
                        pulse = false
                    }
                }
            }
            .onAppear {
                if isRecording {
                    withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                        pulse = true
                    }
                }
            }
    }
}
