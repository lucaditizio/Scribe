import Foundation
import AVFoundation

@Observable
class AudioPlayer: NSObject, AVAudioPlayerDelegate {
    var isPlaying = false
    var currentTime: TimeInterval = 0
    var duration: TimeInterval = 0
    var currentSpeed: Float = 1.0
    var errorLog: String? = nil
    
    private var audioPlayer: AVAudioPlayer?
    private var timer: Timer?
    
    func load(recording: Recording) {
        let documentPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let fileURL = documentPath.appendingPathComponent(recording.audioFilePath)
        
        do {
            #if os(iOS)
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)
            #endif
            
            audioPlayer = try AVAudioPlayer(contentsOf: fileURL)
            audioPlayer?.delegate = self
            audioPlayer?.enableRate = true
            audioPlayer?.prepareToPlay()
            
            duration = audioPlayer?.duration ?? recording.duration
            currentTime = 0
            errorLog = nil // Clear previous errors if successful
            
        } catch let nsError as NSError {
            self.errorLog = "Load Error [\(nsError.domain) - \(nsError.code)]: \(nsError.localizedDescription)"
            print(self.errorLog!)
        } catch {
            self.errorLog = "Unknown Load Error: \(error.localizedDescription)"
            print(self.errorLog!)
        }
    }
    
    func togglePlayback() {
        guard let player = audioPlayer else { 
            if errorLog == nil {
                errorLog = "Cannot Play: AudioPlayer is null but no load error was caught."
            }
            return 
        }
        
        if isPlaying {
            player.pause()
            stopTimer()
        } else {
            player.play()
            startTimer()
        }
        isPlaying = player.isPlaying
    }
    
    func skipForward() {
        guard let player = audioPlayer else { return }
        let newTime = min(player.currentTime + 15.0, duration)
        player.currentTime = newTime
        currentTime = newTime
    }
    
    func skipBackward() {
        guard let player = audioPlayer else { return }
        let newTime = max(player.currentTime - 15.0, 0)
        player.currentTime = newTime
        currentTime = newTime
    }
    
    func cycleSpeed() {
        guard let player = audioPlayer else { return }
        if currentSpeed == 1.0 {
            currentSpeed = 1.5
        } else if currentSpeed == 1.5 {
            currentSpeed = 2.0
        } else {
            currentSpeed = 1.0
        }
        player.rate = currentSpeed
    }
    
    func seek(to time: TimeInterval) {
        guard let player = audioPlayer else { return }
        player.currentTime = max(0, min(time, duration))
        currentTime = player.currentTime
    }
    
    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self = self, let player = self.audioPlayer else { return }
            self.currentTime = player.currentTime
        }
    }
    
    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
    
    // MARK: - AVAudioPlayerDelegate
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        isPlaying = false
        currentTime = duration
        stopTimer()
        
        #if os(iOS)
        do {
            try AVAudioSession.sharedInstance().setActive(false)
        } catch {
            print("Failed to deactivate session post-playback: \(error)")
        }
        #endif
    }
}
