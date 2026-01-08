//
//  ModelSettingsView.swift
//  AIEdgeApp
//

import SwiftUI

struct ModelSettingsView: View {
    let baseViewModel: MLXViewModel
    @State private var models: [(name: String, path: URL, size: Int64)] = []
    @State private var isLoading = false
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationStack {
            List {
                Section("System Prompt") {
                    TextEditor(text: Bindable(baseViewModel).searchSystemPrompt)
                        .frame(minHeight: 100)
                        .font(.caption)
                    
                    Text("This prompt is used when a new conversation starts.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                
                if isLoading {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                    .padding()
                } else if models.isEmpty {
                    VStack(spacing: 8) {
                        Text("No models downloaded")
                            .foregroundColor(.secondary)
                        Text("Download models by selecting them from the model picker and generating text")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
                } else {
                    ForEach(models, id: \.path) { model in
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(model.name)
                                    .font(.headline)
                                Text(baseViewModel.formatBytes(model.size))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            Button {
                                if baseViewModel.deleteModelDirectory(at: model.path) {
                                    loadModels()
                                }
                            } label: {
                                Image(systemName: "trash")
                                    .foregroundColor(.red)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .navigationTitle("Model Storage")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        loadModels()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                loadModels()
            }
        }
    }
    
    private func loadModels() {
        isLoading = true
        // Small delay to show loading state
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            models = baseViewModel.getDownloadedModels()
            isLoading = false
        }
    }
}


