//
//  ConversationPersistence.swift
//  AIEdgeApp
//
//  Created by Jérôme Pitault on 09.03.2026
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
    
    private var indexFileURL: URL {
        conversationsDirectory.appending(path: "index.json")
    }

    // MARK: - Conversation Index Metadata
    
    func loadConversations() -> [Conversation] {
        guard fileManager.fileExists(atPath: indexFileURL.path()) else {
            return []
        }
        
        do {
            let data = try Data(contentsOf: indexFileURL)
            let conversations = try jsonDecoder.decode([Conversation].self, from: data)
            // Sort by most recently updated
            return conversations.sorted { $0.updatedAt > $1.updatedAt }
        } catch {
            print("Failed to load conversations index: \(error)")
            return []
        }
    }
    
    func saveConversations(_ conversations: [Conversation]) {
        do {
            let data = try jsonEncoder.encode(conversations)
            try data.write(to: indexFileURL, options: .atomic)
        } catch {
            print("Failed to save conversations index: \(error)")
        }
    }
    
    func addConversation(_ conversation: Conversation) {
        var all = loadConversations()
        // Replace if exists
        if let index = all.firstIndex(where: { $0.id == conversation.id }) {
            all[index] = conversation
        } else {
            all.append(conversation)
        }
        saveConversations(all)
    }
    
    func updateConversationSummary(id: UUID, newSummary: String) {
        var all = loadConversations()
        if let index = all.firstIndex(where: { $0.id == id }) {
            all[index].summary = newSummary
            all[index].updatedAt = Date()
            saveConversations(all)
        }
    }

    func updateConversationModel(id: UUID, newModelName: String) {
        var all = loadConversations()
        if let index = all.firstIndex(where: { $0.id == id }) {
            all[index].modelName = newModelName
            all[index].updatedAt = Date()
            saveConversations(all)
        }
    }
    
    func deleteConversation(id: UUID) {
        var all = loadConversations()
        all.removeAll { $0.id == id }
        saveConversations(all)
        
        deleteHistory(for: id)
    }
    
    // MARK: - Message History
    
    private func getFileURL(for conversationId: UUID) -> URL {
        return conversationsDirectory.appending(path: "\(conversationId.uuidString).json")
    }
    
    func saveHistory(_ history: [ChatBubble], for conversationId: UUID) {
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
            let fileURL = getFileURL(for: conversationId)
            try data.write(to: fileURL, options: .atomic)
            print("Saved history for \(conversationId) to \(fileURL.path())")
            
            // Auto update modified date in index
            var all = loadConversations()
            if let index = all.firstIndex(where: { $0.id == conversationId }) {
                all[index].updatedAt = Date()
                saveConversations(all)
            }
        } catch {
            print("Failed to save history for \(conversationId): \(error)")
        }
    }
    
    func loadHistory(for conversationId: UUID) -> [ChatBubble]? {
        let fileURL = getFileURL(for: conversationId)
        
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
            print("Failed to load history for \(conversationId): \(error)")
            return nil
        }
    }
    
    func deleteHistory(for conversationId: UUID) {
        let fileURL = getFileURL(for: conversationId)
        
        guard fileManager.fileExists(atPath: fileURL.path()) else {
            return
        }
        
        do {
            try fileManager.removeItem(at: fileURL)
            print("Deleted history for \(conversationId)")
        } catch {
            print("Failed to delete history for \(conversationId): \(error)")
        }
    }
    
    
    // MARK: - Settings Persistence
    
    private func getSettingsFileURL() -> URL {
        return conversationsDirectory.appending(path: "global_settings.json")
    }
    
    func saveSettings(_ settings: ModelSettings) {
        do {
            let data = try jsonEncoder.encode(settings)
            let fileURL = getSettingsFileURL()
            try data.write(to: fileURL, options: .atomic)
            print("Saved global settings to \(fileURL.path())")
        } catch {
            print("Failed to save settings: \(error)")
        }
    }
    
    func loadSettings() -> ModelSettings? {
        let fileURL = getSettingsFileURL()
        
        guard fileManager.fileExists(atPath: fileURL.path()) else {
            return nil
        }
        
        do {
            let data = try Data(contentsOf: fileURL)
            return try jsonDecoder.decode(ModelSettings.self, from: data)
        } catch {
            print("Failed to load settings: \(error)")
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

