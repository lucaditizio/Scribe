import SwiftUI

@available(iOS 18.0, *)
struct AgentGeneratingView: View {
    @Binding var progressText: String
    @Binding var progressValue: Double
    
    @State private var animateMesh = false
    @State private var pulseOpacity = false
    
    var body: some View {
        ZStack {
            // A Plaud-inspired immersive loading background
            // iOS 18 introduces MeshGradient for organic fluid backgrounds
            MeshGradient(
                width: 3,
                height: 3,
                points: [
                    .init(0, 0), .init(0.5, 0), .init(1, 0),
                    .init(0, 0.5), .init(animateMesh ? 0.3 : 0.7, animateMesh ? 0.7 : 0.3), .init(1, 0.5),
                    .init(0, 1), .init(0.5, 1), .init(1, 1)
                ],
                colors: [
                    // Deep aesthetics matching Scribe Theme
                    Color.black, Color.blue.opacity(0.8), Color.black,
                    Color.indigo.opacity(0.6), Color(Theme.primaryColor), Color.purple.opacity(0.6),
                    Color.black, Color.indigo.opacity(0.8), Color.black
                ]
            )
            .ignoresSafeArea()
            .animation(.easeInOut(duration: 4.0).repeatForever(autoreverses: true), value: animateMesh)
            
            VStack(spacing: 40) {
                // Pulsating Central Scribe Icon
                ZStack {
                    Circle()
                        .fill(Color(Theme.primaryColor).opacity(0.2))
                        .frame(width: 140, height: 140)
                        .scaleEffect(pulseOpacity ? 1.2 : 0.8)
                    
                    Circle()
                        .fill(Color(Theme.primaryColor).opacity(0.5))
                        .frame(width: 100, height: 100)
                        .scaleEffect(pulseOpacity ? 1.1 : 0.9)
                    
                    Image(systemName: "waveform.circle.fill")
                        .resizable()
                        .foregroundColor(.white)
                        .frame(width: 80, height: 80)
                }
                .animation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true), value: pulseOpacity)
                
                VStack(spacing: 16) {
                    Text("Artificial Intelligence")
                        .font(.headline)
                        .foregroundColor(.white.opacity(0.7))
                        .textCase(.uppercase)
                    
                    Text(progressText)
                        .font(.title3)
                        .fontWeight(.medium)
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                        .contentTransition(.numericText())
                }
                
                // Progress Bar
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.white.opacity(0.2))
                            .frame(height: 6)
                        
                        Capsule()
                            .fill(Color.white)
                            .frame(width: proxy.size.width * CGFloat(min(max(progressValue, 0), 1.0)), height: 6)
                            .animation(.spring(response: 0.5, dampingFraction: 0.8), value: progressValue)
                    }
                }
                .frame(width: 250, height: 6)
            }
        }
        .onAppear {
            animateMesh = true
            pulseOpacity = true
        }
    }
}

// Fallback for older iOS versions (using standard linear gradient)
struct LegacyAgentGeneratingView: View {
    @Binding var progressText: String
    @Binding var progressValue: Double
    @State private var isAnimating = false
    
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color.black, Color(Theme.primaryColor).opacity(0.8), Color.indigo.opacity(0.6)],
                           startPoint: isAnimating ? .topLeading : .bottomTrailing,
                           endPoint: isAnimating ? .bottomTrailing : .topLeading)
                .ignoresSafeArea()
                .animation(.linear(duration: 5.0).repeatForever(autoreverses: true), value: isAnimating)
            
            VStack(spacing: 30) {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    .scaleEffect(2)
                
                Text(progressText)
                    .font(.headline)
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .padding()
            }
        }
        .onAppear { isAnimating = true }
    }
}

struct GeneratingViewWrapper: View {
    @Binding var text: String
    @Binding var value: Double
    
    var body: some View {
        if #available(iOS 18.0, *) {
            AgentGeneratingView(progressText: $text, progressValue: $value)
        } else {
            LegacyAgentGeneratingView(progressText: $text, progressValue: $value)
        }
    }
}
