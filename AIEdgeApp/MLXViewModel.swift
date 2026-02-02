//
//  MLXViewModel.swift
//  AIEdgeApp
//
//  Created by Jérôme Pitault on 28.12.2025.
//

import Foundation
import Hub
import MLXLLM
import MLXVLM
import MLXLMCommon
import CoreImage
import AVFoundation
internal import Tokenizers
import os
import MLX

#if canImport(UIKit)
import UIKit
#endif



@MainActor
@Observable
class MLXViewModel: NSObject {
    /// The model configuration. It can be a LLM or VLM
    ///
    /// You can checkout MLXLLM.ModelRegistry or MLXVLM.ModelRegistry
    /// for predefined models.
    var modelConfiguration: ModelConfiguration

    /// The model container is used to generate language model output.
    ///
    /// The model container should be loaded via ``ModelFactory.laodContainer`` method.
    ///
    /// There is two type ``ModelFactory``: ``LLMModelFactory`` and ``VLMModelFactory``.
    var modelContainer: ModelContainer?

    /// The output of the language model.
    ///
    /// Call ``generate(prompt:images:)`` method to generate output.
    var output = ""

    /// The generated tokens per second count for the output.
    ///
    /// This property updated after ``generate(prompt:images:)`` method completed.
    var tokensPerSecond: Double = 0

    /// Indicated whetever ``generate(prompt:images:)`` is running or not.
    var isRunning = false

    /// The download progress to track downloading langauge model.
    ///
    /// When you call ``generate(prompt:images:)``, the download begins if the model is missing.
    /// The download progress to track downloading langauge model.
    ///
    /// When you call ``generate(prompt:images:)``, the download begins if the model is missing.
    /// The download progress to track downloading langauge model.
    ///
    /// When you call ``generate(prompt:images:)``, the download begins if the model is missing.
    var downloadProgress: Progress?
    
    /// Any error message occured while the generate process.
    var errorMessage: String?
    
    /// Track the background generation task explicitly for cancellation
    private var currentGenerationTask: Task<String, Error>?

    /// The conversation history for the LLM context
    var messages: [Message] = []
    
    /// The conversation history for the UI
    var chatHistory: [ChatBubble] = []
    
    /// Web search results
    var searchResults: [SearchResult] = []
    
    /// Whether a web search is currently in progress
    var isSearching = false

    /// The system prompt used to instruct the model for web search
    /// The currently active model settings
    var modelSettings: ModelSettings = .default

    /// The system prompt used to instruct the model for web search
    /// Now computed from modelSettings
    /// The dynamic date suffix appended to the prompt
    var datePromptSuffix: String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .full
        let dateString = dateFormatter.string(from: Date())
        return " Today is \(dateString)."
    }

    /// The system prompt used to instruct the model for web search
    /// Now computed from modelSettings
    var searchSystemPrompt: String {
        get {
             return "\(modelSettings.systemPrompt)\(datePromptSuffix)"
        }
        set {
            // setter not strictly needed if binding to modelSettings directly
        }
    }

    /// The download base directory for models
    private var downloadBaseURL: URL {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        guard let documentsURL = paths.first else {
             // Fallback for safety, though extremely unlikely on iOS
             return URL(fileURLWithPath: NSTemporaryDirectory())
        }
        // Try using just "huggingface/models" - HubApi might add "mlx-community" itself
        return documentsURL.appending(path: "huggingface/models")
    }
    
    /// The hub which changes the default download directory
    /// Uses app's document directory which is always accessible on iOS
    private var hub: HubApi

    /// Whether web search is enabled
    var isSearchEnabled = true
    
    /// Flag to track if we need to reload the model when returning to foreground
    private var shouldReloadOnForeground = false

    
    /// Explicitly unloads the current model from memory
    func unloadModel() {
        print("DEBUG: unloadModel called")
        
        // Drop the model container so its memory can be reclaimed
        modelContainer = nil
        
        // Force MLX to release cached memory
        MLX.GPU.clearCache()
        
        // Reset runtime stats / state
        tokensPerSecond = 0
        isRunning = false
        downloadProgress = nil
        
        downloadProgress = nil
        
        // Clear conversation history
        // Save before clearing - CAPTURE HISTORY FIRST
        let currentHistory = self.chatHistory
        let modelName = self.modelConfiguration.name
        
        Task {
            if !currentHistory.isEmpty {
                 await ConversationPersistence.shared.save(history: currentHistory, for: modelName)
            }
        }
        
        messages.removeAll()
        chatHistory.removeAll()
    }
    
    /// Loads the conversation history for the current model
    func loadConversation() async {
        let modelName = modelConfiguration.name
        print("DEBUG: Loading conversation for \(modelName)")
        
        // Load Settings First
        if let settings = await ConversationPersistence.shared.loadSettings(for: modelName) {
            await MainActor.run {
                self.modelSettings = settings
                print("DEBUG: Loaded settings for \(modelName)")
            }
        }
        
        if let history = await ConversationPersistence.shared.load(for: modelName) {
            await MainActor.run {
                self.chatHistory = history
                // Rebuild LLM context from history
                self.rebuildMessagesFromHistory()
                print("DEBUG: Loaded \(history.count) messages from history")
            }
        }
    }
    
    /// Saves the current conversation history and settings
    func saveConversation() async {
        let modelName = modelConfiguration.name
        let history = await MainActor.run { self.chatHistory }
        let settings = await MainActor.run { self.modelSettings }
        
        if !history.isEmpty {
           // print("DEBUG: Saving conversation for \(modelName)")
            await ConversationPersistence.shared.save(history: history, for: modelName)
        }
        
        // Save settings too
        await ConversationPersistence.shared.saveSettings(settings, for: modelName)
    }
    
    /// Explicitly save settings (useful for UI updates)
    func saveSettings() async {
        let modelName = modelConfiguration.name
        let settings = await MainActor.run { self.modelSettings }
        await ConversationPersistence.shared.saveSettings(settings, for: modelName)
    }
    
    /// Rebuilds the LLM 'messages' array from the UI 'chatHistory'
    /// Applies the same memory optimization logic (last N messages)
    private func rebuildMessagesFromHistory() {
        self.messages.removeAll()
        
        // Always add system prompt if search is enabled
        if isSearchEnabled {
            self.messages.append([
                "role": "system",
                "content": self.searchSystemPrompt
            ])
        }
        
        // Take last 6 bubbles (3 turns) + any system/search contexts within them?
        // Actually, simpler: Just mapping the last few valid text bubbles is usually enough.
        // But we need to be careful about matching the format.
        
        let historyToInclude = self.chatHistory.suffix(10) // Take last 10 items to be safe
        
        for bubble in historyToInclude {
            var roleString = "user"
            switch bubble.role {
            case .user: roleString = "user"
            case .assistant: roleString = "assistant"
            case .system: continue // Skip system bubbles (search status) for the LLM context usually, unless it's a tool output
            }
            
            // Handle images if present in user message
            if bubble.role == .user, let images = bubble.images, !images.isEmpty {
                 let modelInputImages: [UserInput.Image] = images.compactMap { CIImage(data: $0) }.map { .ciImage($0) }
                 let content: [String: Any] = [
                    "role": roleString,
                    "content": [
                        ["type": "text", "text": bubble.content]
                    ] + modelInputImages.map { ["type": "image", "_image": $0] }
                 ]
                 self.messages.append(content)
            } else {
                self.messages.append([
                    "role": roleString,
                    "content": bubble.content
                ])
            }
        }
    }

    init(modelConfiguration: ModelConfiguration) {
        print("DEBUG: MLXViewModel INIT - \(modelConfiguration.name)")
        // Initialize stored properties before super.init()
        self.modelConfiguration = modelConfiguration
        
        // Initialize hub - compute downloadBase first
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        let downloadBase: URL
        if let docs = paths.first {
            downloadBase = docs.appending(path: "huggingface/models")
        } else {
            downloadBase = URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: "huggingface/models")
        }
        self.hub = HubApi(downloadBase: downloadBase)
        
        // Now call super.init()
        super.init()
        
        // Debug: Print the path being used
        print("Hub download base: \(downloadBase.path())")
        print("Directory exists: \(FileManager.default.fileExists(atPath: downloadBase.path()))")
        
        // Debug: List all contents of the download directory
        if let contents = try? FileManager.default.contentsOfDirectory(atPath: downloadBase.path()) {
            print("Contents of download directory: \(contents)")
            for item in contents {
                let itemPath = downloadBase.appending(path: item).path()
                var isDir: ObjCBool = false
                if FileManager.default.fileExists(atPath: itemPath, isDirectory: &isDir) {
                    print("  - \(item): \(isDir.boolValue ? "directory" : "file")")
                    if isDir.boolValue {
                        if let subContents = try? FileManager.default.contentsOfDirectory(atPath: itemPath) {
                            print("    Subcontents: \(subContents)")
                        }
                    }
                }
            }
        }
        
        // Set delegate after super.init()
       // speechSynthesizer.delegate = self
        
        // Ensure the download directory exists (now safe to call after super.init())
        createDownloadDirectoryIfNeeded()
        // Ensure the download directory exists (now safe to call after super.init())
        createDownloadDirectoryIfNeeded()
        
        // Setup lifecycle and memory monitoring
        setupLifecycleObservers()
        
        // Removed eager loading in init, now handled by ChatView.task
    }
    
    private func setupLifecycleObservers() {
        #if os(iOS)
        NotificationCenter.default.addObserver(self, selector: #selector(handleBackground), name: UIApplication.didEnterBackgroundNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleForeground), name: UIApplication.willEnterForegroundNotification, object: nil)
        #endif
    }
    
    @objc private func handleBackground() {
        print("App entering background. Unloading model to save memory.")
        // Only unload if we actually have a model loaded
        if modelContainer != nil {
            stop() // Stop generating if running
            // Don't full unloadModel() because we want to keep chat history!
            // We just want to drop the weights.
            unloadModelResourcesOnly()
            shouldReloadOnForeground = true
        }
    }
    
    @objc private func handleForeground() {
        print("App entering foreground.")
        if shouldReloadOnForeground {
            print("Restoring model from background state...")
            shouldReloadOnForeground = false
            Task {
                await loadModel()
            }
        }
    }
    
    /// Unloads ONLY the heavy model weights but keeps chat history
    func unloadModelResourcesOnly() {
        modelContainer = nil
        MLX.GPU.clearCache()
        tokensPerSecond = 0
        isRunning = false
        // intentionally NOT clearing messages/chatHistory
    }
    
    deinit {
        print("DEBUG: MLXViewModel DEINIT")
        NotificationCenter.default.removeObserver(self)
    }
    
    override init() {
        fatalError("Use init(modelConfiguration:) instead")
    }
    
    /// Creates the download directory structure if it doesn't exist
    private func createDownloadDirectoryIfNeeded() {
        let downloadBase = downloadBaseURL
        
        // Create the directory structure if it doesn't exist
        if !FileManager.default.fileExists(atPath: downloadBase.path()) {
            do {
                try FileManager.default.createDirectory(at: downloadBase, withIntermediateDirectories: true, attributes: nil)
                print("Created directory: \(downloadBase.path())")
            } catch {
                print("Failed to create directory: \(error.localizedDescription)")
            }
        } else {
            print("Directory already exists: \(downloadBase.path())")
        }
    }

    /// Deletes the model directory to force re-download
    /// This is useful when the model files are in an incompatible format
    private func deleteModelDirectory() {
        let modelIdString = modelConfiguration.name
        let modelDirName: String
        if modelIdString.hasPrefix("mlx-community/") {
            modelDirName = String(modelIdString.dropFirst("mlx-community/".count))
        } else {
            modelDirName = modelIdString
        }
        
        let modelPath = downloadBaseURL.appending(path: "mlx-community").appending(path: modelDirName)
        
        if FileManager.default.fileExists(atPath: modelPath.path()) {
            do {
                try FileManager.default.removeItem(at: modelPath)
                print("Deleted model directory: \(modelPath.path())")
            } catch {
                print("Failed to delete model directory: \(error.localizedDescription)")
            }
        }
    }

    /// Returns appropriate `ModelFactory` for the ``modelConfiguration``
    ///
    /// If ``modelConfiguration`` is registered in the ``MLXLLM.ModelRegistry`` then it returns ``LLMModelFactory``.
    ///
    /// Otherwise, it returns ``VLMModelFactory``
    private var modelFactory: ModelFactory {
        // If the model is in LLM model registry then it is a LLM
        let isLLM = LLMModelFactory.shared.modelRegistry.models.contains { $0.name == modelConfiguration.name }

        // If the model is a LLM, select LLMFactory. If not, select VLM factory
        return if isLLM {
            LLMModelFactory.shared
        } else {
            VLMModelFactory.shared
        }
    }

    /// Memory usage statistics string for UI display
    var memoryStats: String = "Check Memory"

    /// Helper to log current memory usage and limit
    private func logMemoryUsage(_ label: String = "") {
        var taskInfo = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info>.size) / 4
        let result = withUnsafeMutablePointer(to: &taskInfo) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        
        let used = result == KERN_SUCCESS ? Double(taskInfo.phys_footprint) : 0
        
        #if os(iOS)
        let available = Double(os_proc_available_memory())
        #elseif os(macOS)
        let available = Double(ProcessInfo.processInfo.physicalMemory)
        #endif
        
        let usedStr = ByteCountFormatter.string(fromByteCount: Int64(used), countStyle: .memory)
        let availableStr = ByteCountFormatter.string(fromByteCount: Int64(available), countStyle: .memory)
        
        let stats = "Used: \(usedStr) | Ref: \(availableStr)"
        print("MEMORY DEBUG [\(label)]: \(stats)")
        
        Task { @MainActor in
            self.memoryStats = stats
        }
    }

    /// Loads the ``modelConfiguration`` into ``modelContainer``.
    ///
    /// You don't have to call this method explictly. ``generate(prompt:images:)`` method
    /// calls it when ``modelContainer`` is nil.
    private func loadModel() async {
        do {
            logMemoryUsage("Start loadModel")
            
            // Debug: Print model configuration
            print("Loading model: \(modelConfiguration.name)")
            print("Model ID: \(modelConfiguration.id)")
            
            // Debug: Check if model directory exists
           /* let modelIdString = modelConfiguration.name
            let modelDirName: String
            if modelIdString.hasPrefix("mlx-community/") {
                modelDirName = String(modelIdString.dropFirst("mlx-community/".count))
            } else {
                modelDirName = modelIdString
            } */
            
            // 1. Check Nested Path: huggingface/models/models/owner/repo
            // This matches the structure seen in the user's logs
            let nestedPath: URL
            if modelConfiguration.name.contains("/") {
                 nestedPath = downloadBaseURL.appending(path: "models").appending(path: modelConfiguration.name)
            } else {
                 nestedPath = downloadBaseURL.appending(path: "models").appending(path: "mlx-community").appending(path: modelConfiguration.name)
            }
            
            // 2. Check Simplified Path: huggingface/models/owner/repo
            // (Used by some download logic/older versions)
            let simplifiedPath: URL
            if modelConfiguration.name.contains("/") {
                simplifiedPath = downloadBaseURL.appending(path: modelConfiguration.name)
            } else {
                 simplifiedPath = downloadBaseURL.appending(path: "mlx-community").appending(path: modelConfiguration.name)
            }

            // Determine which path to use - Prioritize the nested path found in logs
            let expectedModelPath: URL
            if FileManager.default.fileExists(atPath: nestedPath.path()) {
                expectedModelPath = nestedPath
                print("Found model at nested path: \(nestedPath.path())")
            } else if FileManager.default.fileExists(atPath: simplifiedPath.path()) {
                expectedModelPath = simplifiedPath
                 print("Found model at simplified path: \(simplifiedPath.path())")
            } else {
                // Default to nested path if neither exists (so download might go there, or we validly fail)
                expectedModelPath = nestedPath
                print("Model not found at any expected path.")
                print("Checked nested: \(nestedPath.path())")
                print("Checked simplified: \(simplifiedPath.path())")
            }
            
            let exists = FileManager.default.fileExists(atPath: expectedModelPath.path())
            print("Final resolved model path: \(expectedModelPath.path())")
            print("Model directory exists: \(exists)")
            /*
            // Check for cache directories that might have old data
            let cachePath = expectedModelPath.appending(path: ".cache")
            if FileManager.default.fileExists(atPath: cachePath.path()) {
                print("WARNING: Found .cache directory, deleting it...")
                try? FileManager.default.removeItem(at: cachePath)
            }
            
            // Also check the parent directories for any cache
            let parentCache = downloadBaseURL.appending(path: ".cache")
            if FileManager.default.fileExists(atPath: parentCache.path()) {
                print("WARNING: Found parent .cache directory, deleting it...")
                try? FileManager.default.removeItem(at: parentCache)
            }
            
            if FileManager.default.fileExists(atPath: expectedModelPath.path()) {
                // Check if the index file has the correct format
                let indexFile = expectedModelPath.appending(path: "model.safetensors.index.json")
                if let data = try? Data(contentsOf: indexFile),
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    // Check if it has the "size" key at root level (MLX expects this)
                    if !json.keys.contains("size") {
                        print("WARNING: model.safetensors.index.json is missing 'size' key. The model may have been downloaded with an incompatible format.")
                        print("Deleting model directory to force re-download in correct format...")
                        deleteModelDirectory()
                    }
                }
            }
            */
            // Try loading - the download should start if files don't exist
            print("Attempting to load model (download will start if needed)...")
            
            var downloadStarted = false
            modelContainer = try await modelFactory.loadContainer(
                hub: hub,
                configuration: modelConfiguration
            ) { progress in
                downloadStarted = true
                print("Download progress: \(progress.fractionCompleted * 100)% - \(progress.localizedDescription ?? "")")
                
                Task { @MainActor in
                    self.downloadProgress = progress
                }
            }
            
            if !downloadStarted && !FileManager.default.fileExists(atPath: expectedModelPath.path()) {
                print("WARNING: Download callback was not called, but model directory doesn't exist. This might indicate a download issue.")
            }
            logMemoryUsage("Model loaded successfully")
        } catch {
            // More detailed error information
            let modelIdString = modelConfiguration.name
            let modelDirName: String
            if modelIdString.hasPrefix("mlx-community/") {
                modelDirName = String(modelIdString.dropFirst("mlx-community/".count))
            } else {
                modelDirName = modelIdString
            }
            
            let expectedModelPath = downloadBaseURL.appending(path: "mlx-community").appending(path: modelDirName)
            
            var detailedError = "Error loading model: \(error.localizedDescription)\n"
            detailedError += "Base path: \(downloadBaseURL.path())\n"
            detailedError += "Expected model path: \(expectedModelPath.path())\n"
            detailedError += "Model directory exists: \(FileManager.default.fileExists(atPath: expectedModelPath.path()))\n"
            
            // Check the actual error
            if let nsError = error as NSError? {
                detailedError += "Error domain: \(nsError.domain)\n"
                detailedError += "Error code: \(nsError.code)\n"
                detailedError += "Error userInfo: \(nsError.userInfo)\n"
                
                // Check if there's a file path in the error
                if let filePath = nsError.userInfo[NSFilePathErrorKey] as? String {
                    detailedError += "Failed file path: \(filePath)\n"
                    detailedError += "File exists: \(FileManager.default.fileExists(atPath: filePath))\n"
                }
                
                // Check for coding path which tells us which key is missing
                if let codingPath = nsError.userInfo["NSCodingPath"] as? [String] {
                    detailedError += "Coding path (missing key location): \(codingPath)\n"
                }
                
                // If it's the size key error, suggest trying without custom hub
                if nsError.code == 4865,
                   let debugDesc = nsError.userInfo["NSDebugDescription"] as? String,
                   debugDesc.contains("size") {
                    detailedError += "\n⚠️ The model files appear to be in an incompatible format.\n"
                    detailedError += "This might be a HubApi configuration issue.\n"
                    detailedError += "Try commenting out the 'hub: hub' parameter to use the default download location.\n"
                }
            }
            
            if let underlyingError = (error as NSError).userInfo[NSUnderlyingErrorKey] as? NSError {
                detailedError += "Underlying error: \(underlyingError.localizedDescription)\n"
                detailedError += "Underlying error domain: \(underlyingError.domain), code: \(underlyingError.code)\n"
                if let filePath = underlyingError.userInfo[NSFilePathErrorKey] as? String {
                    detailedError += "Underlying failed file path: \(filePath)\n"
                }
            }
            
            print(detailedError)
            errorMessage = detailedError
        }
    }

    /// Generates language model output. This is the entry point.
    func generate(prompt: String, images: [Data] = []) async {
        Swift.print("DEBUG: generate called. Prompt len: \(prompt.count), Images: \(images.count)")
        isRunning = true
        self.output = "" // Clear previous output immediately

        // 1. Inject System Prompt if new conversation
        if self.messages.isEmpty {
            if isSearchEnabled {
                self.messages.append([
                    "role": "system",
                    "content": self.searchSystemPrompt
                ])
            }
        }

        // 2. Add User Message
        let modelInputImages: [UserInput.Image] = images.compactMap { CIImage(data: $0) }.map { .ciImage($0) }
        
        let userMessage: Message
        if modelInputImages.isEmpty {
            userMessage = [
                "role": "user",
                "content": prompt
            ]
        } else {
            // Key Fix: Store the actual UserInput.Image object in the dictionary so we can retrieve it later
            // The tokenizer only looks for "type": "image", so adding "_image" is safe
            userMessage = [
                "role": "user",
                "content": [
                    ["type": "text", "text": prompt]
                ] + modelInputImages.map { ["type": "image", "_image": $0] }
            ]
        }
        
        // VLM Memory Optimization: If sending a new image, clear previous history
        // to prevent OOM. We only keep the system prompt.
        if !modelInputImages.isEmpty {
            let systemPrompt = self.messages.first { $0["role"] as? String == "system" }
            self.messages.removeAll()
            print("DEBUG: New image detected. Cleared conversation history to free memory.")
            
            if let sys = systemPrompt {
                self.messages.append(sys)
            }
        }
        
        // Memory Optimization: Prune history if it gets too long
        // Keep system prompt + last 6 messages (3 turns)
        // Memory Optimization: Prune history if it gets too long
        // Keep system prompt + last 6 messages (3 turns)
        if self.messages.count > 10 {
           let firstMessage = self.messages.first
           let suffix = self.messages.suffix(6)
           self.messages = []
           
           // Only preserve the first message if it's a System prompt
            if let first = firstMessage, first["role"] as! String == "system" {
               self.messages.append(first)
           }
           
           self.messages.append(contentsOf: suffix)
           print("DEBUG: Pruned conversation history to save memory")
        }
        
        self.messages.append(userMessage)
        
        // Add User Bubble to UI
        self.chatHistory.append(ChatBubble(role: .user, content: prompt, images: images.isEmpty ? nil : images))
        
        // Auto-save after user message
        await saveConversation()
        
        // 3. Start Recursive Generation Loop
        await generateResponse(images: modelInputImages)
    }
    
    /// Stops the current generation process immediately
    func stop() {
        print("DEBUG: User requested stop. Cancelling generation task.")
        self.isRunning = false
        self.currentGenerationTask?.cancel()
        self.currentGenerationTask = nil
    }

    /// Internal function to handle the generate -> tool -> generate loop iteratively
    /// Memory Optimized: Uses separate perform steps and aggressive cleanup
    private func generateResponse(images: [UserInput.Image]) async {
        // Load the model if it hasn't been loaded yet
        if modelContainer == nil {
            await loadModel()
        }

        guard let modelContainer else { isRunning = false; return }
        
        var depth = 0
        let maxDepth = 5
        var shouldContinue = true
        
        while shouldContinue && isRunning {
            if depth >= maxDepth {
                Task { @MainActor in
                    self.output += "\n\n(System: Max search steps reached. Stopping.)"
                    self.isRunning = false
                }
                break
            }
            
            // Capture messages for the async context safely on MainActor
            let currentMessages = await MainActor.run { self.messages }
            var currentOutput = ""

            // Perform generation in a scoped block
            do {
                print("DEBUG: Starting generation step (depth: \(depth))")
                
                // Capture necessary variables for detached task
                let container = modelContainer
                let inputImages = images
                let messagesSnapshot = currentMessages
                
                // Run generation on background thread to prevent UI freezing
                let task = Task.detached(priority: .userInitiated) {
                    var finalOutput = ""
                    try await container.perform { context in
                        // FIX: Cumulative Image Collection
                        // We must find ALL images in the history to match the placeholder tokens
                        var cumulativeImages: [UserInput.Image] = []
                        
                        for msg in messagesSnapshot {
                            if let content = msg["content"] as? [[String: Any]] {
                                for part in content {
                                    if let type = part["type"] as? String, type == "image",
                                       let imgObj = part["_image"] as? UserInput.Image {
                                        cumulativeImages.append(imgObj)
                                    }
                                }
                            }
                        }
                        
                        // FIX: Sanitize messages for Jinja (remove _image key which causes runtime errors)
                        let sanitizedMessages = messagesSnapshot.map { msg -> Message in
                            var newMsg = msg
                            if let content = msg["content"] as? [[String: Any]] {
                                newMsg["content"] = content.map { part in
                                    var newPart = part
                                    newPart.removeValue(forKey: "_image")
                                    return newPart
                                }
                            }
                            return newMsg
                        }
                        
                        // Create user input with SANITIZED messages
                        var userInput = UserInput(messages: sanitizedMessages)
                        userInput.processing.resize = CGSize(width: 448, height: 448)
                        
                        // If we found historical images, use them.
                        // Otherwise fallback to inputImages (current turn only) - keeping original behavior for edge cases
                        if !cumulativeImages.isEmpty {
                            userInput.images = cumulativeImages
                            print("DEBUG: Providing \(cumulativeImages.count) cumulative images to model")
                        } else if !inputImages.isEmpty {
                            userInput.images = inputImages
                             print("DEBUG: Providing \(inputImages.count) current-turn images to model")
                        }
                        
                        // Create LM input
                        let input = try await context.processor.prepare(input: userInput)
                        
                        // Generate output
                        let result = try MLXLMCommon.generate(input: input, parameters: .init(), context: context) { tokens in
                            // Critical: Stop if the task is cancelled
                            if Task.isCancelled { return .stop }
                            
                            let text = context.tokenizer.decode(tokens: tokens)
                            finalOutput = text
                            
                            Task { @MainActor in
                                self.output = text
                                
                                // Streaming UI Update
                                if let lastIndex = self.chatHistory.indices.last, self.chatHistory[lastIndex].role == .assistant {
                                    self.chatHistory[lastIndex].content = text
                                    self.chatHistory[lastIndex].isStreaming = true // Keep it animating
                                } else {
                                    // Create new assistant bubble if not exists
                                    self.chatHistory.append(ChatBubble(role: .assistant, content: text, isStreaming: true))
                                }
                            }
                            
                            // FIX: Handle missing EOS token for Gemma models and detect SEARCH command
                            if text.contains("<end of turn>") || text.contains("<end_of_turn>") {
                                return .stop
                            }
                            
                            // FIX: Detect SEARCH command but wait for the complete line (newline)
                            if let searchRange = text.range(of: "SEARCH:"), text[searchRange.upperBound...].contains("\n") {
                                return .stop
                            }
                            
                            return .more
                        }
                        
                        // Capture stats
                        Task { @MainActor in self.tokensPerSecond = result.tokensPerSecond }
                    }
                    return finalOutput
                }
                self.currentGenerationTask = task
                currentOutput = try await task.value
            } catch {
                print("DEBUG: Generation error: \(error)")
                Task { @MainActor in
                    self.errorMessage = error.localizedDescription
                     if error.localizedDescription.contains("memory") {
                         self.errorMessage = "Out of memory. Try a smaller model."
                    }
                }
                shouldContinue = false
            }
            
            if !shouldContinue {
                // Fix: Ensure partial output is saved to history to maintain User/Assistant alternation
                // Fallback to self.output if currentOutput is empty (e.g. task cancellation threw before assignment)
                let partialText = currentOutput.isEmpty ? self.output : currentOutput
                
                if !partialText.isEmpty {
                     await MainActor.run {
                         // Double check we haven't already appended it to avoid duplicates
                         if self.messages.last?["role"] as? String != "assistant" {
                             self.messages.append(["role": "assistant", "content": partialText])
                         }
                     }
                     // Auto-save partial result
                     await self.saveConversation()
                }
                break 
            }

            // Logic Check (Search vs Final)
             let trimmedOutput = currentOutput.trimmingCharacters(in: .whitespacesAndNewlines)
            
            if let range = trimmedOutput.range(of: "SEARCH:") {
                let query = String(trimmedOutput[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                
                await MainActor.run {
                    Swift.print("DEBUG: Model requested search: \(query)")
                    self.output = "🔍 Searching web for: \"\(query)\"..."
                    
                    // Add assistant request
                    self.messages.append([
                        "role": "assistant",
                        "content": currentOutput
                    ])
                }
                
                // Perform the search
                // Strict memory limit: 5 results, max 600 chars total
                let searchResultsText: String
                
                // Add System Bubble for searching
                await MainActor.run {
                    self.chatHistory.append(ChatBubble(role: .system, content: "🔍 Searching web for: \"\(query)\"", isStreaming: true))
                }
                
                do {
                    let results = try await WebSearcher.shared.search(query: query)
                    
                    if results.isEmpty {
                        searchResultsText = "Search returned no results."
                        await MainActor.run {
                             if let idx = self.chatHistory.indices.last {
                                 self.chatHistory[idx].content = "❌ No results found."
                                 self.chatHistory[idx].isStreaming = false
                             }
                        }
                    } else {
                        // VERY Aggressive truncation
                        // Only top 5 results
                        let topResults = results.prefix(5)
                        var combined = "Search Results:\n" + topResults.map { "- [\($0.title)](\($0.link)): \($0.snippet)" }.joined(separator: "\n\n")
                        
                        // Initial soft cap
                        if combined.count > 1000 {
                             combined = String(combined.prefix(1000)) + "\n...(truncated)"
                        }
                        searchResultsText = combined
                        
                        await MainActor.run {
                             if let idx = self.chatHistory.indices.last {
                                 self.chatHistory[idx].content = "✅ Found \(topResults.count) results."
                                 self.chatHistory[idx].isStreaming = false
                             }
                        }
                    }
                } catch {
                    searchResultsText = "Search failed: \(error.localizedDescription)"
                    await MainActor.run {
                         if let idx = self.chatHistory.indices.last {
                             self.chatHistory[idx].content = "⚠️ Search failed."
                             self.chatHistory[idx].isStreaming = false
                         }
                    }
                }
                
                // Append results
                 await MainActor.run {
                    self.messages.append([
                        "role": "user",
                        "content": "Here are the search results:\n\(searchResultsText)\n\nPlease answer using these results."
                    ])
                }

                // Auto-save search results
                await self.saveConversation()
                
                // Continue loop
                depth += 1
                continue
            }
            
            // Final Answer
             await MainActor.run {
                print("DEBUG: No search detected, appending final answer")
                
                // Ensure we have an assistant bubble to update if we were just streaming
                 if self.chatHistory.last?.role == .assistant {
                     // It's already there, just ensure isStreaming is false
                     var lastBubble = self.chatHistory[self.chatHistory.count - 1]
                     lastBubble.isStreaming = false
                     self.chatHistory[self.chatHistory.count - 1] = lastBubble
                 } else {
                     // Should not happen usually if streaming, but safe fallback
                     self.chatHistory.append(ChatBubble(role: .assistant, content: currentOutput, isStreaming: false))
                 }
                 
                self.messages.append([
                    "role": "assistant",
                    "content": currentOutput
                ])
            }
            
            // Auto-save after final answer
            await self.saveConversation()
            
            shouldContinue = false
        }
        
        await MainActor.run {
            self.isRunning = false
        }
        logMemoryUsage("DEBUG: generate finished")
    }
    
    /// Performs a web search and updates `searchResults`
    func performSearch(query: String) async {
        print("DEBUG: performSearch called with query: \(query)")
        isSearching = true
        searchResults = [] // Clear previous results
        
        do {
            let results = try await WebSearcher.shared.search(query: query)
            Task { @MainActor in
                self.searchResults = results
                self.isSearching = false
            }
            print("DEBUG: found \(results.count) results")
        } catch {
            print("DEBUG: search error: \(error)")
            Task { @MainActor in
                self.errorMessage = "Search failed: \(error.localizedDescription)"
                self.isSearching = false
            }
        }
    }

    // Speech methods removed
    
    /// Creates ``UserInput.Prompt`` from prompt string and images
    ///
    /// If images is empty, return ``UserInput.Prompt/text`` case with the prompt.
    ///
    /// Otherwise, it will create messages in Qwen2 VL format and return ``UserInput.Prompt/messages``.


    
    /// Gets the list of all downloaded model directories
    func getDownloadedModels() -> [(name: String, path: URL, size: Int64)] {
        var allModels: [(name: String, path: URL, size: Int64)] = []
        
        let basePath = downloadBaseURL
        print("Base download path: \(basePath.path())")
        
        // Check multiple possible locations
        let possiblePaths = [
            basePath.appending(path: "mlx-community"),
            basePath.appending(path: "models").appending(path: "mlx-community"),
            basePath.appending(path: "models").appending(path: "models").appending(path: "mlx-community")
        ]
        
        // Also search recursively from the base path
        allModels.append(contentsOf: searchForModelsRecursively(startingAt: basePath, depth: 0, maxDepth: 3))
        
        // Remove duplicates based on path
        var uniqueModels: [URL: (name: String, path: URL, size: Int64)] = [:]
        for model in allModels {
            uniqueModels[model.path] = model
        }
        
        let result = Array(uniqueModels.values).sorted { $0.name < $1.name }
        print("Total unique models found: \(result.count)")
        for model in result {
            print("  - \(model.name) at \(model.path.path())")
        }
        
        return result
    }
    
    /// Recursively searches for model directories
    private func searchForModelsRecursively(startingAt url: URL, depth: Int, maxDepth: Int) -> [(name: String, path: URL, size: Int64)] {
        var models: [(name: String, path: URL, size: Int64)] = []
        
        guard depth < maxDepth else { return models }
        guard FileManager.default.fileExists(atPath: url.path()) else { return models }
        
        if let contents = try? FileManager.default.contentsOfDirectory(atPath: url.path()) {
            for item in contents {
                // Skip hidden files and cache directories
                if item.hasPrefix(".") {
                    continue
                }
                
                let itemPath = url.appending(path: item)
                var isDir: ObjCBool = false
                
                guard FileManager.default.fileExists(atPath: itemPath.path(), isDirectory: &isDir),
                      isDir.boolValue else {
                    continue
                }
                
                // Check if this directory looks like a model directory
                // (has config.json or model.safetensors files)
                let hasConfig = FileManager.default.fileExists(atPath: itemPath.appending(path: "config.json").path())
                let hasModelFile = FileManager.default.fileExists(atPath: itemPath.appending(path: "model.safetensors").path()) ||
                                   FileManager.default.fileExists(atPath: itemPath.appending(path: "model.safetensors.index.json").path())
                
                if hasConfig || hasModelFile {
                    // This looks like a model directory
                    let size = calculateDirectorySize(at: itemPath)
                    print("Found model directory: \(item) at \(itemPath.path())")
                    models.append((name: item, path: itemPath, size: size))
                } else {
                    // Recursively search in subdirectories
                    models.append(contentsOf: searchForModelsRecursively(startingAt: itemPath, depth: depth + 1, maxDepth: maxDepth))
                }
            }
        }
        
        return models
    }
    
    /// Helper function to get models from a specific path
    private func getModelsFromPath(_ modelsPath: URL) -> [(name: String, path: URL, size: Int64)] {
        var models: [(name: String, path: URL, size: Int64)] = []
        
        if let contents = try? FileManager.default.contentsOfDirectory(atPath: modelsPath.path()) {
            print("Found \(contents.count) items in directory: \(contents)")
            for item in contents {
                let itemPath = modelsPath.appending(path: item)
                var isDir: ObjCBool = false
                if FileManager.default.fileExists(atPath: itemPath.path(), isDirectory: &isDir),
                   isDir.boolValue {
                    // Skip .cache directories
                    if item.hasPrefix(".") {
                        continue
                    }
                    // Check if it's actually a model (has config.json)
                    let hasConfig = FileManager.default.fileExists(atPath: itemPath.appending(path: "config.json").path())
                    if hasConfig {
                        // Calculate directory size
                        let size = calculateDirectorySize(at: itemPath)
                        print("Found model: \(item), size: \(size) bytes")
                        models.append((name: item, path: itemPath, size: size))
                    }
                }
            }
        }
        
        return models.sorted { $0.name < $1.name }
    }
    
    /// Calculates the total size of a directory
    private func calculateDirectorySize(at url: URL) -> Int64 {
        var totalSize: Int64 = 0
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles],
            errorHandler: nil
        ) else {
            return 0
        }
        
        for case let fileURL as URL in enumerator {
            if let fileSize = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                totalSize += Int64(fileSize)
            }
        }
        
        return totalSize
    }
    
    /// Deletes a model directory
    func deleteModelDirectory(at path: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: path.path()) else {
            return false
        }
        
        do {
            try FileManager.default.removeItem(at: path)
            return true
        } catch {
            print("Failed to delete model directory: \(error.localizedDescription)")
            return false
        }
    }
    
    /// Formats bytes to human-readable string
    func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
    
    /// Helper to extract text from a Message dictionary
    func getMessageText(_ message: Message) -> String {
        guard let content = message["content"] else { return "" }
        
        if let text = content as? String {
            return text
        }
        
        if let parts = content as? [[String: Any]] {
            return parts.compactMap { part in
                if let type = part["type"] as? String, type == "text",
                   let text = part["text"] as? String {
                    return text
                }
                return nil
            }.joined(separator: "\n")
        }
        
        return ""
    }
}
