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

struct ChatView: View {
    let modelConfiguration: ModelConfiguration
    
    @State private var vm: MLXViewModel
    @State private var prompt: String = ""
    @State private var selectedImages: [Data] = []
    
    @State private var showingPhotoPicker: Bool = false
    @State private var photoSelection: PhotosPickerItem?
    @State private var showingSettings: Bool = false
    
    @FocusState private var isFocused: Bool
    
    @State private var generationTask: Task<Void, Never>?

    private var displayName: String {
        if let lastPart = modelConfiguration.name.split(separator: "/").last {
            return String(lastPart)
        }
        return modelConfiguration.name
    }
    
    init(modelConfiguration: ModelConfiguration) {
        self.modelConfiguration = modelConfiguration
        _vm = State(initialValue: MLXViewModel(modelConfiguration: modelConfiguration))
    }
    
    
    var body: some View {
        VStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(vm.chatHistory) { bubble in
                            ChatBubbleView(bubble: bubble)
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
            .padding()
        }
        .navigationTitle("")
        #if(os(iOS))
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 2) {
                    Text(displayName)
                        .font(.headline)
                    Text("\(vm.tokensPerSecond, format: .number.precision(.fractionLength(2))) t/s • \(vm.memoryStats)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
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
        if let url = try? result.get(), let data = try? Data(contentsOf: url) {
            selectedImages = [data]
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
