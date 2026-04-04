import SwiftUI

struct RecordButtonView: View {
    @Bindable var bleRecorder: BleAudioRecorder
    let connectionManager: DeviceConnectionManager
    @Binding var currentDuration: TimeInterval
    @Binding var isRecording: Bool
    var onRecordingFinished: (TimeInterval, URL?) -> Void
    
    private var isConnected: Bool {
        switch connectionManager.connectionState {
        case .connected, .initialized, .bound:
            return true
        default:
            return false
        }
    }
    
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
        .disabled(!isConnected)
        .opacity(isConnected ? 1.0 : 0.5)
        .onChange(of: bleRecorder.state) { _, newState in
            isRecording = (newState == .recording)
        }
        .onChange(of: bleRecorder.currentDuration) { _, newDuration in
            currentDuration = newDuration
        }
    }
    
    private func toggleRecording() {
        switch bleRecorder.state {
        case .idle:
            bleRecorder.startRecording()
        case .recording:
            let fileURL = bleRecorder.stopRecording()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                onRecordingFinished(bleRecorder.currentDuration, fileURL)
            }
        case .stopped:
            bleRecorder.startRecording()
        }
    }
}
