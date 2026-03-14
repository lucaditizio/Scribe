import Foundation
import AVFoundation
import Observation

#if canImport(UIKit)
import UIKit
#endif

@Observable
class AudioRecorder: NSObject, AVAudioRecorderDelegate {
    var isRecording = false
    var currentTime: TimeInterval = 0
    var currentRecordingSessionID: String?
    
    private var audioRecorder: AVAudioRecorder?
    private var timer: Timer?
    
    // To ensure strict sequential control and memory usage
    private let engineQueue = DispatchQueue(label: "com.scribe.audioEngine", qos: .userInitiated)
    
    override init() {
        super.init()
        setupAudioSession()
    }
    
    private func setupAudioSession() {
        #if os(iOS)
        do {
            let session = AVAudioSession.sharedInstance()
            // .playAndRecord to allow capturing. Allow bluetooth/external routing.
            try session.setCategory(.playAndRecord, mode: .default, options: [.allowBluetooth, .defaultToSpeaker])
            try session.setActive(true)
            
            // Listen for route changes to prioritize external USB-C mic if plugged in
            NotificationCenter.default.addObserver(self,
                                                   selector: #selector(handleRouteChange),
                                                   name: AVAudioSession.routeChangeNotification,
                                                   object: nil)
        } catch {
            print("Failed to set up audio session: \(error.localizedDescription)")
        }
        #endif
    }
    
    #if os(iOS)
    @objc private func handleRouteChange(notification: Notification) {
        guard let userInfo = notification.userInfo,
              let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else { return }
        
        switch reason {
        case .newDeviceAvailable:
            let session = AVAudioSession.sharedInstance()
            for input in session.currentRoute.inputs {
                print("New audio input available: \(input.portName) (\(input.portType))")
                if input.portType == .usbAudio || input.portType == .headsetMic {
                    do {
                        try session.setPreferredInput(input)
                        print("Preferred input set to external USB/Headset Mic.")
                    } catch {
                        print("Error setting preferred input: \(error)")
                    }
                }
            }
        case .oldDeviceUnavailable:
            print("Audio device disconnected.")
        default: break
        }
    }
    #else
    @objc private func handleRouteChange(notification: Notification) { }
    #endif
    
    func toggleRecording() -> String? {
        if isRecording {
            stopRecording()
            triggerHapticFeedback()
            return currentRecordingSessionID
        } else {
            startRecording()
            triggerHapticFeedback()
            return nil
        }
    }
    
    private func startRecording() {
        #if os(iOS)
        let audioSession = AVAudioSession.sharedInstance()
        audioSession.requestRecordPermission { [weak self] allowed in
            guard allowed, let self = self else {
                print("Recording permission denied")
                return
            }
            
            DispatchQueue.main.async {
                do {
                    try audioSession.setCategory(.playAndRecord, mode: .default, options: [.allowBluetooth, .defaultToSpeaker])
                    try audioSession.setActive(true)
                } catch {
                    print("Failed to activate audio session: \(error)")
                    return
                }
                
                self.currentRecordingSessionID = UUID().uuidString
                let documentPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                let audioFilename = documentPath.appendingPathComponent("\(self.currentRecordingSessionID!).m4a")
                
                // Scribe constraints: 48kHz mono
                let settings: [String: Any] = [
                    AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                    AVSampleRateKey: 48000,
                    AVNumberOfChannelsKey: 1,
                    AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
                ]
                
                do {
                    self.audioRecorder = try AVAudioRecorder(url: audioFilename, settings: settings)
                    self.audioRecorder?.delegate = self
                    self.audioRecorder?.prepareToRecord()
                    
                    let success = self.audioRecorder?.record() ?? false
                    
                    if success {
                        self.isRecording = true
                        self.currentTime = 0
                        self.startTimer()
                    } else {
                        print("Recording failed to start even though permissions were granted.")
                        do { try audioSession.setActive(false) } catch {}
                    }
                } catch {
                    print("Could not start recording: \(error.localizedDescription)")
                }
            }
        }
        #endif
    }
    
    private func stopRecording() {
        self.audioRecorder?.stop()
        self.audioRecorder = nil
        self.isRecording = false
        self.stopTimer()
        
        #if os(iOS)
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            print("Failed to deactivate audio session: \(error)")
        }
        #endif
    }
    
    private func startTimer() {
        timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self = self, let recorder = self.audioRecorder else { return }
            if recorder.isRecording {
                self.currentTime = recorder.currentTime
            }
        }
        if let timer = timer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }
    
    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
    
    private func triggerHapticFeedback() {
        #if os(iOS)
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.prepare()
        generator.impactOccurred()
        #endif
    }
}
