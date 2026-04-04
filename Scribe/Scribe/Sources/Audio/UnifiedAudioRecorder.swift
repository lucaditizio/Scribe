import Foundation
import Observation

enum AudioSource {
    case bluetooth
    case internalMic
}

@Observable
class UnifiedAudioRecorder {
    private let bleRecorder: BleAudioRecorder
    private let internalRecorder: AudioRecorder
    private var currentSource: AudioSource = .bluetooth
    
    var isRecording: Bool {
        switch currentSource {
        case .bluetooth:
            return bleRecorder.state == .recording
        case .internalMic:
            return internalRecorder.isRecording
        }
    }
    
    var currentDuration: TimeInterval {
        switch currentSource {
        case .bluetooth:
            return bleRecorder.currentDuration
        case .internalMic:
            return internalRecorder.currentTime
        }
    }
    
    var activeSource: AudioSource { currentSource }
    
    init(bleRecorder: BleAudioRecorder) {
        self.bleRecorder = bleRecorder
        self.internalRecorder = AudioRecorder()
    }
    
    func setSource(_ source: AudioSource) {
        guard !isRecording else {
            print("[UnifiedAudioRecorder] Cannot switch source while recording")
            return
        }
        currentSource = source
    }
    
    func toggleRecording() -> (url: URL?, duration: TimeInterval)? {
        switch currentSource {
        case .bluetooth:
            if bleRecorder.state == .idle || bleRecorder.state == .stopped {
                bleRecorder.startRecording()
                return nil
            } else if bleRecorder.state == .recording {
                return bleRecorder.stopRecording()
            }
            return nil
            
        case .internalMic:
            if let sessionID = internalRecorder.toggleRecording() {
                let documentPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                let url = documentPath.appendingPathComponent("\(sessionID).m4a")
                return (url, internalRecorder.currentTime)
            }
            return nil
        }
    }
}
