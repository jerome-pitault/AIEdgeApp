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

#if canImport(UIKit)
import UIKit
#endif
#if canImport(AppKit)
import AppKit
#endif

struct ContentView: View {
    /// All models you want to expose in the dropdown
    private let availableModels: [ModelConfiguration] = [
        LLMRegistry.deepSeekR1_1_5B_4bit,
        LLMRegistry.qwen2_5Coder_1_5B_4bit,
        MLXVLM.VLMRegistry.qwen2_VL_2B_Instruct_4bit,
        //LLMRegistry.qwen2_VL_2B_Instruct_4bit,
        LLMRegistry.qwen3_4B_4bit,
        LLMRegistry.Qwen3_8B_MLX_4bit,
        LLMRegistry.granite_4_0_h_micro_4bit,
        //LLMRegistry.Apertus_8B_2509_4bit,
        LLMRegistry.ministral3_3B_4bit,
        LLMRegistry.gemma_3n_E4B_it_lm_4bit,
        //LLMRegistry.Voxtral_Mini_3B_2507_bf16,
        MLXVLM.VLMRegistry.Qwen3_VL_4B_Instruct_3bit
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
    @FocusState private var isFocused: Bool

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
                    
                    if vm.isRunning {
                        Button {
                            vm.stop()
                        } label: {
                            Image(systemName: "stop.circle.fill")
                                .resizable()
                                .frame(width: 30, height: 30) // Match roughly the touch target of others
                                .foregroundStyle(.red)
                        }
                    } else {
                        // Search toggle button
                        Button {
                            vm.isSearchEnabled.toggle()
                        } label: {
                            Image(systemName: vm.isSearchEnabled ? "globe" : "globe.slash") // Using globe to represent web search
                                .foregroundColor(vm.isSearchEnabled ? .green : .gray)
                        }
                    }
                    
                    // Stop speech button (only show when speaking)

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
                            
                            // Delete button
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

                    TextField("Prompt", text: $prompt)
                        .textFieldStyle(.roundedBorder)
                        .focused($isFocused)

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
        // Dismiss keyboard
        isFocused = false
        
        // Capture current prompt and clear it immediately
        let currentPrompt = prompt
        prompt = ""
        
        // Cancel any existing task
        generationTask?.cancel()
        
        generationTask = Task {
            await vm.generate(prompt: currentPrompt, images: selectedImages)
        }
    }

#if(os(iOS))
    private func addImage() {
        Task {
            if let data = try? await photoSelection?.loadTransferable(type: Data.self) {
                print("DEBUG: UI - Image loaded from picker. Size: \(data.count) bytes")
                selectedImages = [data]
            } else {
                print("DEBUG: UI - Failed to load image or cleared")
                selectedImages = []
            }
        }
    }
#elseif(os(macOS))
    private func addImage(_ result: Result<URL, any Error>) {
        if let url = try? result.get(), let data = try? Data(contentsOf: url) {
            print("DEBUG: UI - Image loaded from file. Size: \(data.count) bytes")
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
                    VStack(alignment: .leading, spacing: 8) {
                        Text(bubble.content)
                        
                        if let images = bubble.images, !images.isEmpty {
                            ForEach(Array(images.enumerated()), id: \.offset) { _, imageData in
                                #if os(iOS)
                                if let uiImage = UIImage(data: imageData) {
                                    Image(uiImage: uiImage)
                                        .resizable()
                                        .scaledToFit()
                                        .frame(maxHeight: 200)
                                        .cornerRadius(8)
                                }
                                #elseif os(macOS)
                                if let nsImage = NSImage(data: imageData) {
                                    Image(nsImage: nsImage)
                                        .resizable()
                                        .scaledToFit()
                                        .frame(maxHeight: 200)
                                        .cornerRadius(8)
                                }
                                #endif
                            }
                        }
                    }
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
