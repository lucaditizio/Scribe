import SwiftUI

struct RecordButtonView: View {
    @Bindable var unifiedRecorder: UnifiedRecorder
    @Binding var currentDuration: TimeInterval
    @Binding var isRecording: Bool
    var onRecordingFinished: (RecordingOutput?) -> Void

    var body: some View {
        Button(action: toggleRecording) {
            ZStack {
                Circle()
                    .fill(Theme.scribeRed.opacity(0.3))
                    .frame(width: 80, height: 80)
                    .scaleEffect(isRecording ? 1.5 : 1.0)
                    .opacity(isRecording ? 0 : 0.8)
                    .animation(
                        isRecording ? Animation.easeInOut(duration: 1.5).repeatForever(autoreverses: false) : .default,
                        value: isRecording
                    )

                Circle()
                    .fill(isRecording ? Theme.scribeRed.opacity(0.8) : Theme.scribeRed)
                    .frame(width: 70, height: 70)
                    .shadow(color: Theme.scribeRed.opacity(0.5), radius: 10, x: 0, y: 5)

                if isRecording {
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
        .opacity(unifiedRecorder.isAvailable ? 1.0 : 0.5)
        .disabled(!unifiedRecorder.isAvailable)
        .onChange(of: unifiedRecorder.isRecording) { _, newState in
            isRecording = newState
        }
        .onChange(of: unifiedRecorder.currentDuration) { _, newDuration in
            currentDuration = newDuration
        }
    }

    private func toggleRecording() {
        if unifiedRecorder.isRecording {
            unifiedRecorder.stopRecording { result in
                if let result = result {
                    onRecordingFinished(result)
                }
            }
        } else {
            unifiedRecorder.startRecording()
        }
    }
}
