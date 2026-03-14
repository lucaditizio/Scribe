import SwiftUI

struct RecordButtonView: View {
    @Bindable var audioRecorder: AudioRecorder
    var onRecordingFinished: (TimeInterval, String) -> Void
    
    // State for pulse animation
    @State private var pulseScale: CGFloat = 1.0
    
    var body: some View {
        Button(action: {
            let finalizedSessionID = audioRecorder.toggleRecording()
            if let finalizedSessionID = finalizedSessionID {
                // Recording stopped, we have a duration and a file ID
                // Wait briefly for recorder to fully stop and write file
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    onRecordingFinished(audioRecorder.currentTime, finalizedSessionID)
                }
            }
        }) {
            ZStack {
                // Pulse effect background
                Circle()
                    .fill(Theme.scribeRed.opacity(0.3))
                    .frame(width: 80, height: 80)
                    .scaleEffect(audioRecorder.isRecording ? 1.5 : 1.0)
                    .opacity(audioRecorder.isRecording ? 0 : 0.8)
                    .animation(
                        audioRecorder.isRecording ? Animation.easeInOut(duration: 1.5).repeatForever(autoreverses: false) : .default,
                        value: audioRecorder.isRecording
                    )
                
                Circle()
                    .fill(audioRecorder.isRecording ? Theme.scribeRed.opacity(0.8) : Theme.scribeRed)
                    .frame(width: 70, height: 70)
                    .shadow(color: Theme.scribeRed.opacity(0.5), radius: 10, x: 0, y: 5)
                
                // Icon state change
                if audioRecorder.isRecording {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.white)
                        .frame(width: 24, height: 24)
                } else {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(.white)
                }
            }
        }
    }
}
