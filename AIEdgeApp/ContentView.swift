//
//  ContentView.swift
//  AIEdgeApp
//
//  Created by Jérôme Pitault on 28.12.2025.
//

import SwiftUI
import MLXLLM
import MLXVLM
import MLXLMCommon
import PhotosUI
import AVFoundation

struct ContentView: View {
    /// All models you want to expose in the dropdown
    private let availableModels: [ModelConfiguration] = [
        LLMRegistry.deepSeekR1_1_5B_4bit,
        LLMRegistry.qwen2_5Coder_1_5B_4bit,
        MLXVLM.VLMRegistry.qwen2_VL_2B_Instruct_4bit,
        //LLMRegistry.qwen2_VL_2B_Instruct_4bit,
        LLMRegistry.qwen3_4B_4bit,
        LLMRegistry.granite_4_0_h_micro_4bit,
        //LLMRegistry.Apertus_8B_2509_4bit,
        LLMRegistry.ministral3_3B_4bit,
        //LLMRegistry.Voxtral_Mini_3B_2507_bf16
    ]
    
    /// Precomputed model options for the picker
    private var modelOptions: [(id: ModelConfiguration.Identifier, label: String, config: ModelConfiguration)] {
        availableModels.map { ($0.id, String(describing: $0.id), $0) }
    }

    // Selected model index used by the Picker
    @State private var selectedModelIndex: Int
    
    /// The current view model, recreated when the model changes1
    @State private var vm: MLXViewModel

    init() {
        // Register custom models once
        LLMModelFactory.shared.modelRegistry.registerCustomModels()

        // Choose an initial model (DeepSeek here)
        let initialModel = LLMRegistry.qwen3_4B_4bit
        let initialIndex = 3  //

        _selectedModelIndex = State(initialValue: initialIndex)
        _vm = State(initialValue: MLXViewModel(modelConfiguration: initialModel))
    }

    @State private var prompt: String = ""
    @State private var selectedImages: [Data] = []

    @State private var showingPhotoPicker: Bool = false
    @State private var photoSelection: PhotosPickerItem?
    @State private var showingSettings = false

    var body: some View {
        NavigationStack {
            VStack {
                // Model picker
                Picker("Model", selection: $selectedModelIndex) {
                    ForEach(Array(availableModels.enumerated()), id: \.offset) { index, model in
                        Text(String(describing: model.id))
                            .tag(index)
                    }
                }
                .pickerStyle(.menu)
                .onChange(of: selectedModelIndex) { _, newIndex in
                    if newIndex < availableModels.count {
                        // Cancel any running generation
                        generationTask?.cancel()

                        // Explicitly unload the old model to free memory
                        vm.unloadModel()

                        let newConfig = availableModels[newIndex]
                        vm = MLXViewModel(modelConfiguration: newConfig)
                    }
                }

                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 12) {
                            ForEach(vm.chatHistory) { bubble in
                                ChatBubbleView(bubble: bubble)
                            }
                        }
                        .padding()
                    }
                    // .onChange(of: vm.chatHistory.last?.content) removed to prevent scrolling jitter during streaming
                    .onChange(of: vm.chatHistory.count) { _, _ in
                         if let lastId = vm.chatHistory.last?.id {
                             withAnimation {
                                 proxy.scrollTo(lastId, anchor: .bottom)
                             }
                         }
                    }
                }

                HStack {
                    Button {
                        showingPhotoPicker = true
                    } label: {
                        Image(systemName: "photo.badge.plus")
                    }
                    
                    // Search toggle button
                    Button {
                        vm.isSearchEnabled.toggle()
                    } label: {
                        Image(systemName: vm.isSearchEnabled ? "globe" : "globe.slash") // Using globe to represent web search
                            .foregroundColor(vm.isSearchEnabled ? .green : .gray)
                    }
                    
                    // Stop speech button (only show when speaking)


                    TextField("Prompt", text: $prompt)
                        .textFieldStyle(.roundedBorder)

                    Button(action: generate) {
                        Image(systemName: "paperplane.fill")
                            .symbolEffect(.pulse, options: .repeating, isActive: vm.isRunning)
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(sendButtonDisabled)
                }
            }
            .padding()
            .navigationTitle("AIEdgeApp")
#if(os(macOS))
            .navigationSubtitle(vm.modelConfiguration.name)
#endif
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showingSettings = true
                    } label: {
                        Image(systemName: "gearshape.fill")
                    }
                }
                
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

                ToolbarItem {
                    Button(action: reset) {
                        TokensPerSecondView(value: vm.tokensPerSecond, memoryStats: vm.memoryStats)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .sheet(isPresented: $showingSettings) {
            ModelSettingsView(baseViewModel: vm)
        }
#if(os(iOS))
        .photosPicker(isPresented: $showingPhotoPicker, selection: $photoSelection)
        .onChange(of: photoSelection, addImage)
#elseif(os(macOS))
        .fileImporter(isPresented: $showingPhotoPicker, allowedContentTypes: [.image], onCompletion: addImage)
#endif
    }

    @State private var generationTask: Task<Void, Never>?

    private func generate() {
        // Cancel any existing task
        generationTask?.cancel()
        
        generationTask = Task {
            await vm.generate(prompt: prompt, images: selectedImages)
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
        if let url = try? result.get(), let data = try? Data(contentsOf: url) {
            selectedImages = [data]
        } else {
            selectedImages = []
        }
    }
#endif

    private func reset() {
        generationTask?.cancel()
        vm.unloadModel() // Using unloadModel ensures full cleanup including audio
        
        vm.output = ""
        vm.tokensPerSecond = 0
        prompt = ""
        selectedImages = []
    }

    private var sendButtonDisabled: Bool {
        vm.isRunning ||
        prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        (vm.downloadProgress != nil && !vm.downloadProgress!.isFinished)
    }
}

struct ChatBubbleView: View {
    let bubble: ChatBubble
    
    var body: some View {
        HStack {
            if bubble.role == .user {
                Spacer()
            }
            
            VStack(alignment: bubble.role == .user ? .trailing : .leading) {
                if bubble.role == .system {
                    Text(bubble.content)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(8)
                        .background(Color.secondary.opacity(0.1))
                        .clipShape(Capsule())
                } else {
                    Text(bubble.content)
                        .padding(12)
                        .background(bubble.role == .user ? Color.blue : Color.gray.opacity(0.2))
                        .foregroundColor(bubble.role == .user ? .white : .primary)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                }
            }
            
            if bubble.role != .user {
                Spacer()
            }
        }
        .id(bubble.id)
    }
}

#Preview {
    ContentView()
}
