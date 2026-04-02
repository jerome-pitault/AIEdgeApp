import Foundation
import Qwen3TTS
import AudioCommon
import MLX
import AVFoundation
import Observation
import NaturalLanguage

@MainActor
@Observable
public class TTSManager {

    public var isSynthesizing: Bool = false
    public var isLoading: Bool = false
    public var progress: Double = 0
    public var status: String = "Idle"
    
    // Track how many audio buffers are currently queued for playback
    private var queuedBuffersCount: Int = 0
    
    // Track generation to allow early stopping Mid-sentence
    private var synthesisTask: Task<Void, Error>?
    
    private var model: Qwen3TTSModel?
    private var audioEngine = AVAudioEngine()
    private var playerNode = AVAudioPlayerNode()
    
    private let playFormat = AVAudioFormat(standardFormatWithSampleRate: 24000, channels: 1)!
    
    public init() {
        setupAudioSession()
        audioEngine.attach(playerNode)
        audioEngine.connect(playerNode, to: audioEngine.mainMixerNode, format: playFormat)
    }
    
    private func setupAudioSession() {
        #if os(iOS)
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
        } catch {
            print("Failed to set up audio session: \(error.localizedDescription)")
        }
        #endif
    }
    
    public func loadModel(variant: String = "base") async throws {
        // Skip if already loaded or loading
        if model != nil || isLoading { return }
        
        isLoading = true
        defer { isLoading = false }
        
        // Clear MLX GPU cache to free up memory before loading the TTS model
        #if os(iOS)
        MLX.GPU.clearCache()
        #endif
        
        status = "Loading Qwen3-TTS..."
        progress = 0
        model = try await Qwen3TTSModel.fromPretrained(
            modelId: variant == "base" ? TTSModelVariant.base.rawValue : TTSModelVariant.customVoice.rawValue,
            progressHandler: { prog, status in
                print(String(format: "TTS Progress: [%.1f%%] %@", prog * 100, status))
                Task { @MainActor in
                    self.progress = prog
                    self.status = status
                }
            }
        )
        status = "Qwen3-TTS loaded"
    }
    
    public func unloadModel() {
        model = nil
        status = "Unloaded"
        progress = 0
    }
    
    public func speak(text: String, speaker: String? = nil, language: String = "english") async throws {
        // Cancel any ongoing speech
        stop()
        
        isSynthesizing = true
        
        // Load model on demand if not already loaded
        if model == nil {
            try await loadModel()
        }
        
        guard let model = model else {
            isSynthesizing = false
            status = "Error: Model failed to load"
            return
        }
        
        // 1. Split text into sentences using NLTokenizer
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text
        var sentences = [String]()
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { tokenRange, _ in
            let sentence = String(text[tokenRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !sentence.isEmpty {
                sentences.append(sentence)
            }
            return true
        }
        
        guard !sentences.isEmpty else {
            isSynthesizing = false
            return
        }
        
        // 2. Start the Audio Engine so it's ready to receive queued buffers
        if !audioEngine.isRunning {
            try audioEngine.start()
        }
        playerNode.play()
        
        // 3. Process sentences sequentially
        synthesisTask = Task {
            var completedSentences = 0
            let totalSentences = sentences.count
            self.queuedBuffersCount = 0
            
            for sentence in sentences {
                // Check if user hit stop
                if Task.isCancelled { break }
                
                // Throttle generation: wait if we already have 2 sentences queued up
                while self.queuedBuffersCount >= 2 && !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
                }
                
                if Task.isCancelled { break }
                
                status = "Synthesizing sentence \(completedSentences + 1)/\(totalSentences)..."
                
                // Perform generation off the main thread
                let samples = try await Task.detached {
                    let s = model.synthesize(text: sentence, language: language, speaker: speaker)
                    #if os(iOS)
                    MLX.GPU.clearCache()
                    #endif
                    return s
                }.value
                
                if Task.isCancelled { break }
                
                status = "Playing sentence \(completedSentences + 1)/\(totalSentences)..."
                
                self.queuedBuffersCount += 1
                try playAudioBuffer(samples: samples, isLast: (completedSentences == totalSentences - 1))
                
                completedSentences += 1
            }
            
            // If task was cancelled during synthesis, make sure state is reset
            if Task.isCancelled {
                isSynthesizing = false
                status = "Idle"
            }
        }
    }
    
    public func stop() {
        synthesisTask?.cancel()
        synthesisTask = nil
        playerNode.stop()
        audioEngine.stop()
        queuedBuffersCount = 0
        isSynthesizing = false
        status = "Stopped"
    }
    
    private func playAudioBuffer(samples: [Float], isLast: Bool) throws {
        guard !samples.isEmpty else {
            queuedBuffersCount -= 1
            return
        }
        let buffer = AVAudioPCMBuffer(pcmFormat: playFormat, frameCapacity: AVAudioFrameCount(samples.count))!
        buffer.frameLength = buffer.frameCapacity
        
        for i in 0..<samples.count {
            buffer.floatChannelData![0][i] = samples[i]
        }
        
        // Schedule buffer to play sequentially. 
        // If it's the last sentence, we set a completion handler to mark synthesis as finished after audio finishes playing.
        playerNode.scheduleBuffer(buffer, at: nil, options: .interruptsAtLoop) { [weak self] in
            Task { @MainActor in
                self?.queuedBuffersCount -= 1
                if isLast {
                    self?.isSynthesizing = false
                    self?.status = "Idle"
                }
            }
        }
    }
}
