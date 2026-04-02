import Foundation
import Qwen3ASR
import Qwen3TTS
import Observation

@MainActor
@Observable
public class SpeechManager {
    public var asrManager = ASRManager()
    public var ttsManager = TTSManager()
    public var recorder = AudioRecorder()
    
    public var isRecording: Bool { recorder.isRecording }
    public var isSynthesizing: Bool { ttsManager.isSynthesizing }
    public var currentlySpeakingId: UUID?
    
    public init() {}
    
    public func loadModels() async throws {
        try await asrManager.loadModel()
        try await ttsManager.loadModel()
    }
    
    public func startListening() async throws {
        try await recorder.startRecording()
    }
    
    public func stopListening() async -> String {
        recorder.stopRecording()
        let transcription = await asrManager.transcribe(audio: recorder.audioData)
        return transcription
    }
    
    public func speak(text: String) async {
        currentlySpeakingId = nil // Global speak doesn't have an ID
        try? await ttsManager.speak(text: text)
    }
    
    public func toggleSpeak(id: UUID, text: String) async {
        if currentlySpeakingId == id && isSynthesizing {
            ttsManager.stop()
            currentlySpeakingId = nil
        } else {
            // Stop any current speech before starting new one
            if isSynthesizing {
                ttsManager.stop()
            }
            
            currentlySpeakingId = id
            try? await ttsManager.speak(text: text)
            
            // Note: currentlySpeakingId will be cleared by the @Observation 
            // of ttsManager.isSynthesizing in the View, but we can also
            // monitor it here if we want more robust logic.
        }
    }
}
