import Foundation
import AVFoundation
import Observation

@Observable
public class AudioRecorder {

    private var audioEngine = AVAudioEngine()
    private var inputNode: AVAudioInputNode { audioEngine.inputNode }
    private var recordingFormat: AVAudioFormat?
    
    public var isRecording = false
    public var audioData: [Float] = []
    
    public init() {}
    
    public func startRecording(sampleRate: Double = 24000) async throws {
        audioData.removeAll()
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
        try session.setActive(true)
        
        // Ensure record permission is granted
        await session.requestRecordPermission { granted in
            if !granted {
                print("❌ Microphone permission denied")
            }
        }
        #endif
        let hardwareFormat = inputNode.outputFormat(forBus: 0)
        let recordingFormat = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        
        let converter = AVAudioConverter(from: hardwareFormat, to: recordingFormat)!
        
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: hardwareFormat) { (buffer, time) in
            let inputCallback: AVAudioConverterInputBlock = { inNumPackets, outStatus in
                outStatus.pointee = .haveData
                return buffer
            }
            
            let outputBuffer = AVAudioPCMBuffer(pcmFormat: recordingFormat, frameCapacity: AVAudioFrameCount(Double(buffer.frameLength) * sampleRate / hardwareFormat.sampleRate) + 100)!
            
            var error: NSError?
            converter.convert(to: outputBuffer, error: &error, withInputFrom: inputCallback)
            
            if let floatData = outputBuffer.floatChannelData {
                let frameCount = Int(outputBuffer.frameLength)
                var newSamples: [Float] = []
                for i in 0..<frameCount {
                    newSamples.append(floatData[0][i])
                }
                let samplesToAppend = newSamples
                Task { @MainActor in
                    self.audioData.append(contentsOf: samplesToAppend)
                }
            }
        }
        
        try audioEngine.start()
        isRecording = true
    }
    
    public func stopRecording() {
        inputNode.removeTap(onBus: 0)
        audioEngine.stop()
        isRecording = false
    }
}
