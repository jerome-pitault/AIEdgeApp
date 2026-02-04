//
//  ModelRow.swift
//  AIEdgeApp
//
//  Created by Jérôme Pitault on 28.12.2025.
//

import SwiftUI
import MLXLLM
import MLXLMCommon
import MLXEmbedders


import MLXVLM

struct ModelRow: View {
    let model: MLXLMCommon.ModelConfiguration
    let isSelected: Bool
    
    @State private var modelSize: String?
    
    // Computed property to strip the prefix (e.g., "mlx-community/")
    var displayName: String {
        if let lastPart = model.name.split(separator: "/").last {
            return String(lastPart)
        }
        return model.name
    }
    
    var isVLM: Bool {
        // Check VLM registry
        let isRegisteredVLM = VLMModelFactory.shared.modelRegistry.models.contains { $0.name == model.name }
        // Check simple heuristic for custom models
        let isNameVLM = model.name.lowercased().contains("vl") || model.name.lowercased().contains("vision")
        return isRegisteredVLM || isNameVLM
    }
    
    var body: some View {
        HStack(spacing: 12) {
            // Avatar / Icon
            ZStack {
                Circle()
                    .fill(isVLM ? Color.purple : Color.blue)
                    .frame(width: 50, height: 50)
                
                if isVLM {
                    Image(systemName: "camera.fill")
                        .font(.title2)
                        .foregroundStyle(.white)
                } else {
                    Text(String(displayName.prefix(1)).uppercased())
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundStyle(.white)
                }
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(displayName)
                    .font(.headline)
                    .lineLimit(1)
                
                if let size = modelSize {
                    Text(size)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            Spacer()
        }
        .padding(.vertical, 0)
        .contentShape(Rectangle()) // Make full row tappable
        .task {
            calculateSize()
        }
    }
    
    private func calculateSize() {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        guard let documentsURL = paths.first else { return }
        let downloadBaseURL = documentsURL.appending(path: "huggingface/models")
        
        // Logic replicated from MLXViewModel to find possible paths
        let nestedPath: URL
        if model.name.contains("/") {
            nestedPath = downloadBaseURL.appending(path: "models").appending(path: model.name)
        } else {
            nestedPath = downloadBaseURL.appending(path: "models").appending(path: "mlx-community").appending(path: model.name)
        }
        
        let simplifiedPath: URL
        if model.name.contains("/") {
            simplifiedPath = downloadBaseURL.appending(path: model.name)
        } else {
            simplifiedPath = downloadBaseURL.appending(path: "mlx-community").appending(path: model.name)
        }
        
        let fileManager = FileManager.default
        let modelPath: URL
        
        if fileManager.fileExists(atPath: nestedPath.path()) {
            modelPath = nestedPath
        } else if fileManager.fileExists(atPath: simplifiedPath.path()) {
            modelPath = simplifiedPath
        } else {
            return
        }
        
        // Calculate size recursively
        if let size = try? fileManager.allocatedSizeOfDirectory(at: modelPath) {
             let formatter = ByteCountFormatter()
             formatter.allowedUnits = [.useGB, .useMB]
             formatter.countStyle = .file
             modelSize = formatter.string(fromByteCount: Int64(size))
        }
    }
}

extension FileManager {
    func allocatedSizeOfDirectory(at directoryURL: URL) throws -> UInt64 {
        var accumulatedSize: UInt64 = 0
        
        let resourceKeys: Set<URLResourceKey> = [.isRegularFileKey, .fileAllocatedSizeKey, .totalFileAllocatedSizeKey]
        let enumerator = self.enumerator(at: directoryURL, includingPropertiesForKeys: Array(resourceKeys), options: [])
        
        while let fileURL = enumerator?.nextObject() as? URL {
            let resourceValues = try fileURL.resourceValues(forKeys: resourceKeys)
            if resourceValues.isRegularFile ?? false {
                accumulatedSize += UInt64(resourceValues.totalFileAllocatedSize ?? resourceValues.fileAllocatedSize ?? 0)
            }
        }
        
        return accumulatedSize
    }
}
