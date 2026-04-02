//
//  ChatView.swift
//  AIEdgeApp
//
//  Created by Jérôme Pitault on 28.12.2025.
//

import SwiftUI
import MLXLLM
import MLXVLM
import MLXLMCommon
import PhotosUI
import MLX

struct HashableModelConfiguration: Hashable, Identifiable {
    let base: ModelConfiguration
    var id: String { base.name } // use model name as identifier (unique enough for display)
    
    static func ==(lhs: HashableModelConfiguration, rhs: HashableModelConfiguration) -> Bool {
        lhs.base.name == rhs.base.name
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(base.name)
    }
}

struct ChatView: View {
    let modelConfiguration: ModelConfiguration
    
    @State private var vm: MLXViewModel
    @State private var selectedModel: HashableModelConfiguration
    @State private var prompt: String = ""
    @State private var selectedImages: [Data] = []
    
    @State private var showingPhotoPicker: Bool = false
    @State private var photoSelection: PhotosPickerItem?
    @State private var showingSettings: Bool = false
    
    @FocusState private var isFocused: Bool
    
    @State private var generationTask: Task<Void, Never>?
    
    init(modelConfiguration: ModelConfiguration, conversationId: UUID? = nil) {
        self.modelConfiguration = modelConfiguration
        _vm = State(initialValue: MLXViewModel(modelConfiguration: modelConfiguration, conversationId: conversationId))
        let initial = HashableModelConfiguration(base: modelConfiguration)
        _selectedModel = State(initialValue: initial)
    }
    
    private var compatibleModels: [HashableModelConfiguration] {
        ModelWithRequirement.compatible.map { HashableModelConfiguration(base: $0) }
    }
    
    var body: some View {
        VStack {
            VStack(spacing: 2) {
                Picker("Model", selection: $selectedModel) {
                    ForEach(compatibleModels) { config in
                        let nameParts = config.base.name.split(separator: "/")
                        let displayName = nameParts.last.map(String.init) ?? config.base.name
                        Text(displayName)
                            .tag(config)
                    }
                }
                .onChange(of: selectedModel) { _, newSelection in
                    Task {
                        await vm.unloadModel() // Unload the old model and clear state
                        vm.modelConfiguration = newSelection.base
                        Memory.clearCache()
                        await vm.loadConversation() // Load any existing conversation for the new model
                    }
                }
                .pickerStyle(.menu)
                .font(.headline)
                
                Text("\(vm.tokensPerSecond, format: .number.precision(.fractionLength(2))) t/s • \(vm.memoryStats)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.top)
            
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(vm.chatHistory) { bubble in
                            ChatBubbleView(
                                bubble: bubble,
                                isSpeaking: vm.speechManager.currentlySpeakingId == bubble.id && (vm.speechManager.isSynthesizing || vm.speechManager.ttsManager.isLoading),
                                onSpeak: {
                                    Task {
                                        await vm.toggleSpeak(id: bubble.id, text: bubble.content)
                                    }
                                }
                            )
                        }
                    }
                    .padding()
                }
                .onChange(of: vm.chatHistory.count) { _, _ in
                     if let lastId = vm.chatHistory.last?.id {
                         withAnimation {
                             proxy.scrollTo(lastId, anchor: .bottom)
                         }
                     }
                }
                .onChange(of: vm.chatHistory.last?.content) { _, _ in
                     // Auto-scroll during text streaming
                     if let lastId = vm.chatHistory.last?.id {
                         proxy.scrollTo(lastId, anchor: .bottom)
                     }
                }
            }
            
            HStack {
                if vm.isVLM {
                    Button {
                        showingPhotoPicker = true
                    } label: {
                        Image(systemName: "photo.badge.plus")
                    }
                }
                
                if vm.isRunning {
                    Button {
                        vm.stop()
                    } label: {
                        Image(systemName: "stop.circle.fill")
                            .resizable()
                            .frame(width: 30, height: 30)
                            .foregroundStyle(.red)
                    }
                } /*else {
                    // Search toggle button
                    Button {
                        vm.isSearchEnabled.toggle()
                    } label: {
                        Image(systemName: vm.isSearchEnabled ? "globe" : "globe.slash")
                            .foregroundColor(vm.isSearchEnabled ? .green : .gray)
                    }
                }*/
                
                // Selected Image Preview
                if let firstImage = selectedImages.first {
                    ZStack(alignment: .topTrailing) {
                        #if os(iOS)
                        if let uiImage = UIImage(data: firstImage) {
                            Image(uiImage: uiImage)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 40, height: 40)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        #elseif os(macOS)
                        if let nsImage = NSImage(data: firstImage) {
                            Image(nsImage: nsImage)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 40, height: 40)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        #endif
                        
                        Button {
                            selectedImages = []
                            photoSelection = nil
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.white, .black.opacity(0.7))
                                .font(.system(size: 16))
                        }
                        .buttonStyle(.plain)
                        .offset(x: 5, y: -5)
                    }
                    .padding(.trailing, 4)
                }

                HStack(spacing: 8) {
                    Button {
                        vm.toggleListening()
                    } label: {
                        Image(systemName: vm.speechManager.isRecording ? "mic.fill" : "mic")
                            .font(.system(size: 20))
                            .foregroundStyle(vm.speechManager.isRecording ? .red : .blue)
                            .frame(width: 30, height: 30) // Minimum touch target size
                    }
                    .buttonStyle(.plain)

                    TextField("Prompt", text: $prompt)
                        .textFieldStyle(.roundedBorder)
                        .focused($isFocused)
                }

                Button(action: generate) {
                    Image(systemName: "paperplane.fill")
                        .symbolEffect(.pulse, options: .repeating, isActive: vm.isRunning)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(sendButtonDisabled)
            }
            .padding()
        }
        .navigationTitle("")
        #if(os(iOS))
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            /*
            ToolbarItem(placement: .principal) {
                VStack(spacing: 2) {
                    Text(displayName)
                        .font(.headline)
                    Text("\(vm.tokensPerSecond, format: .number.precision(.fractionLength(2))) t/s • \(vm.memoryStats)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            */
            
            if let errorMessage = vm.errorMessage {
                ToolbarItem {
                    AppErrorView(errorMessage: errorMessage)
                }
            }

            if let progress = vm.downloadProgress, !progress.isFinished {
                ToolbarItem {
                    DownloadProgressView(progress: progress)
                }
            }
            
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingSettings = true
                } label: {
                    Image(systemName: "gearshape")
                }
            }
        }
        .sheet(isPresented: $showingSettings) {
             ModelSettingsView(baseViewModel: vm, availableModels: [vm.modelConfiguration])
        }
        .onDisappear {
            // Unload model when leaving the chat view
            vm.unloadModel()
        }
        .task {
            // Reload conversation when entering the view
            // This fixes the issue where messages disappear after going back
            await vm.loadConversation()
        }
        #if(os(iOS))
        .photosPicker(isPresented: $showingPhotoPicker, selection: $photoSelection)
        .onChange(of: photoSelection, addImage)
        #elseif(os(macOS))
        .fileImporter(isPresented: $showingPhotoPicker, allowedContentTypes: [.image], onCompletion: addImage)
        #endif
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ASRTranscriptionReceived"))) { notification in
            if let text = notification.object as? String {
                self.prompt = text
            }
        }
    }
    
    private func generate() {
        isFocused = false
        let currentPrompt = prompt
        prompt = ""
        generationTask?.cancel()
        
        generationTask = Task {
            await vm.generate(prompt: currentPrompt, images: selectedImages)
        }
    }
    
    #if(os(iOS))
    private func addImage() {
        Task {
            if let data = try? await photoSelection?.loadTransferable(type: Data.self) {
                selectedImages = [data]
            } else {
                selectedImages = []
            }
        }
    }
    #elseif(os(macOS))
    private func addImage(_ result: Result<URL, any Error>) {
        if let url = try? result.get() {
            // Access security-scoped resource
            let accessing = url.startAccessingSecurityScopedResource()
            defer {
                if accessing {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            
            if let data = try? Data(contentsOf: url) {
                selectedImages = [data]
            } else {
                 print("Failed to read data from URL: \(url)")
                 selectedImages = []
            }
        } else {
            selectedImages = []
        }
    }
    #endif
    
    private var sendButtonDisabled: Bool {
        vm.isRunning ||
        prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        (vm.downloadProgress != nil && !vm.downloadProgress!.isFinished)
    }
}

