//
//  ModelSettingsView.swift
//  AIEdgeApp
//

import SwiftUI
import MLXLMCommon

struct ModelSettingsView: View {
    let baseViewModel: MLXViewModel
    @State private var modelStatus: (isDownloaded: Bool, size: String)? = nil
    @State private var showingDeleteConfirmation = false
    @State private var showingClearConversationConfirmation = false
    @State private var modelPath: URL?
    @Environment(\.dismiss) var dismiss
    
    let availableModels: [ModelConfiguration]
    
    var body: some View {
        NavigationStack {
            List {
                Section("System Prompt") {
                    TextEditor(text: Bindable(baseViewModel).modelSettings.systemPrompt)
                        .frame(minHeight: 100)
                        .font(.caption)
                    
                    Text("This prompt is used when a new conversation starts.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                
                Section("Dynamic Context (Read-Only)") {
                    Text(baseViewModel.datePromptSuffix)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    Text("This date information is automatically appended to your system prompt.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                
                Section("Current Model") {
                    if let config = availableModels.first {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(getDisplayName(for: config))
                                        .font(.headline)
                                    
                                    if let status = modelStatus {
                                        if status.isDownloaded {
                                            Text("Downloaded • \(status.size)")
                                                .font(.caption)
                                                .foregroundColor(.green)
                                        } else {
                                            Text("Not downloaded")
                                                .font(.caption)
                                                .foregroundColor(.orange)
                                        }
                                    }
                                }
                                
                                Spacer()
                                
                                // HuggingFace Link
                                if let url = getHuggingFaceURL(for: config) {
                                    Link(destination: url) {
                                        Image(systemName: "globe")
                                            .foregroundColor(.blue)
                                            .padding(.horizontal, 8)
                                    }
                                    .buttonStyle(.plain)
                                }
                                
                                // Delete button (only visible if downloaded)
                                if let status = modelStatus, status.isDownloaded {
                                    Button {
                                        showingDeleteConfirmation = true
                                    } label: {
                                        Image(systemName: "trash")
                                            .foregroundColor(.red)
                                            .padding(.horizontal, 8)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            
                            Text("Tap the globe icon to view model details and documentation on HuggingFace.")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .padding(.top, 4)
                        }
                        .padding(.vertical, 4)
                    }
                }
                
                Section("Conversation Management") {
                    Button(role: .destructive) {
                        showingClearConversationConfirmation = true
                    } label: {
                        HStack {
                            Image(systemName: "trash.circle")
                            Text("Clear Conversation History")
                        }
                    }
                    
                    Text("This will delete all messages in the current conversation. This action cannot be undone.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .alert("Delete Model?", isPresented: $showingDeleteConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Delete", role: .destructive) {
                    deleteCurrentModel()
                }
            } message: {
                Text("This will free up space on your device. You can re-download the model later if needed.")
            }
            .alert("Clear Conversation?", isPresented: $showingClearConversationConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Clear", role: .destructive) {
                    clearConversation()
                }
            } message: {
                Text("This will permanently delete all messages in this conversation. This action cannot be undone.")
            }
            .toolbar {
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        Task {
                             await baseViewModel.saveSettings()
                             dismiss()
                        }
                    }
                }
            }
            .onDisappear {
                Task {
                    await baseViewModel.saveSettings()
                }
            }
            .onAppear {
                checkModelStatus()
            }
        }
    }
    
    private func getDisplayName(for config: ModelConfiguration) -> String {
        if let lastPart = config.name.split(separator: "/").last {
            return String(lastPart)
        }
        return config.name
    }
    
    private func getHuggingFaceURL(for config: ModelConfiguration) -> URL? {
        return URL(string: "https://huggingface.co/\(config.id)")
    }
    
    private func checkModelStatus() {
        guard let config = availableModels.first else { return }
        
        let allModels = baseViewModel.getDownloadedModels()
        let displayName = getDisplayName(for: config)
        
        if let found = allModels.first(where: { $0.name == displayName }) {
            modelStatus = (isDownloaded: true, size: baseViewModel.formatBytes(found.size))
            modelPath = found.path
        } else {
            modelStatus = (isDownloaded: false, size: "")
            modelPath = nil
        }
    }
    
    private func deleteCurrentModel() {
        guard let path = modelPath else { return }
        
        if baseViewModel.deleteModelDirectory(at: path) {
            // Refresh status after deletion
            checkModelStatus()
        }
    }
    
    private func clearConversation() {
        Task {
            await baseViewModel.clearConversation()
            dismiss()
        }
    }
    

}


