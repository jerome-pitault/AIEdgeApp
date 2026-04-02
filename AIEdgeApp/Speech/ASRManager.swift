import Foundation
import Qwen3ASR
import AudioCommon
import MLX
import AVFoundation
import Observation

@MainActor
@Observable
public class ASRManager {

    public var transcription: String = ""
    public var isTranscribing: Bool = false
    public var isLoading: Bool = false
    public var progress: Double = 0
    public var status: String = "Idle"
    
    private var model: Qwen3ASRModel?
    private let sampleRate: Int = 16000 // ASR models usually expect 16kHz
    
    public init() {}
    
    public func loadModel(modelId: String = ASRModelSize.small.defaultModelId) async throws {
        // Skip if already loaded or loading
        if model != nil || isLoading { return }
        
        isLoading = true
        defer { isLoading = false }
        
        status = "Loading model..."
        progress = 0
        
        model = try await Qwen3ASRModel.fromPretrained(
            modelId: modelId,
            progressHandler: { prog, status in
                print(String(format: "ASR Progress: [%.1f%%] %@", prog * 100, status))
                Task { @MainActor in
                    self.progress = prog
                    self.status = status
                }
            }
        )
        status = "Model loaded"
    }
    
    public func unloadModel() {
        model = nil
        status = "Unloaded"
        progress = 0
    }
    
    public func transcribe(audio: [Float]) async -> String {
        guard let model = model else {
            status = "Error: Model not loaded"
            return ""
        }
        
        isTranscribing = true
        status = "Transcribing..."
        
        let result = await Task.detached {
            model.transcribe(audio: audio, sampleRate: self.sampleRate)
        }.value
        
        transcription = result
        isTranscribing = false
        status = "Transcription complete"
        return result
    }
}
