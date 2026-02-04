//
//  ConversationPersistence.swift
//  AIEdgeApp
//
//  Created by AI Agent.
//

import Foundation

/// A Codable representation of a ChatBubble for persistence
struct ChatBubbleSnapshot: Codable {
    let id: UUID
    let role: ChatRole
    let content: String
    let images: [Data]?
    let timestamp: Date
}

/// Actor to handle safe concurrent access to conversation files
actor ConversationPersistence {
    static let shared = ConversationPersistence()
    
    private let fileManager = FileManager.default
    private let jsonEncoder = JSONEncoder()
    private let jsonDecoder = JSONDecoder()
    
    private init() {
        jsonEncoder.outputFormatting = .prettyPrinted
        jsonEncoder.dateEncodingStrategy = .iso8601
        jsonDecoder.dateDecodingStrategy = .iso8601
    }
    
    private var conversationsDirectory: URL {
        let paths = fileManager.urls(for: .documentDirectory, in: .userDomainMask)
        let documentsURL = paths[0]
        let conversationsURL = documentsURL.appending(path: "Conversations")
        
        if !fileManager.fileExists(atPath: conversationsURL.path()) {
            try? fileManager.createDirectory(at: conversationsURL, withIntermediateDirectories: true)
        }
        
        return conversationsURL
    }
    
    private func getFileURL(for modelName: String) -> URL {
        // Sanitize model name for filename safety
        let safeName = modelName.replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
        return conversationsDirectory.appending(path: "\(safeName).json")
    }
    
    func save(history: [ChatBubble], for modelName: String) {
        let snapshots = history.map { bubble in
            ChatBubbleSnapshot(
                id: bubble.id,
                role: bubble.role,
                content: bubble.content,
                images: bubble.images,
                timestamp: Date() // Capture save time approx
            )
        }
        
        do {
            let data = try jsonEncoder.encode(snapshots)
            let fileURL = getFileURL(for: modelName)
            try data.write(to: fileURL, options: .atomic)
            print("Saved conversation for \(modelName) to \(fileURL.path())")
        } catch {
            print("Failed to save conversation for \(modelName): \(error)")
        }
    }
    
    func load(for modelName: String) -> [ChatBubble]? {
        let fileURL = getFileURL(for: modelName)
        
        guard fileManager.fileExists(atPath: fileURL.path()) else {
            return nil
        }
        
        do {
            let data = try Data(contentsOf: fileURL)
            let snapshots = try jsonDecoder.decode([ChatBubbleSnapshot].self, from: data)
            
            return snapshots.map { snapshot in
                ChatBubble(
                    role: snapshot.role,
                    content: snapshot.content,
                    images: snapshot.images,
                    isStreaming: false
                )
            }
        } catch {
            print("Failed to load conversation for \(modelName): \(error)")
            return nil
        }
    }
    
    func delete(for modelName: String) {
        let fileURL = getFileURL(for: modelName)
        
        guard fileManager.fileExists(atPath: fileURL.path()) else {
            return
        }
        
        do {
            try fileManager.removeItem(at: fileURL)
            print("Deleted conversation for \(modelName)")
        } catch {
            print("Failed to delete conversation for \(modelName): \(error)")
        }
    }
    
    
    // MARK: - Settings Persistence
    
    private func getSettingsFileURL(for modelName: String) -> URL {
        let safeName = modelName.replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
        return conversationsDirectory.appending(path: "\(safeName)_settings.json")
    }
    
    func saveSettings(_ settings: ModelSettings, for modelName: String) {
        do {
            let data = try jsonEncoder.encode(settings)
            let fileURL = getSettingsFileURL(for: modelName)
            try data.write(to: fileURL, options: .atomic)
            print("Saved settings for \(modelName) to \(fileURL.path())")
        } catch {
            print("Failed to save settings for \(modelName): \(error)")
        }
    }
    
    func loadSettings(for modelName: String) -> ModelSettings? {
        let fileURL = getSettingsFileURL(for: modelName)
        
        guard fileManager.fileExists(atPath: fileURL.path()) else {
            return nil
        }
        
        do {
            let data = try Data(contentsOf: fileURL)
            return try jsonDecoder.decode(ModelSettings.self, from: data)
        } catch {
            print("Failed to load settings for \(modelName): \(error)")
            return nil
        }
    }
}

/// A Codable representation of per-model settings
struct ModelSettings: Codable, Equatable {
    var systemPrompt: String
    
    static let `default` = ModelSettings(
        systemPrompt: "You are a helpful assistant with access to a web search tool. To use it, start your response with 'SEARCH: <query>'. Stop generating after issuing the command. I will parse the results and give them to you."
    )
}
