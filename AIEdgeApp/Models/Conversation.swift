//
//  Conversation.swift
//  AIEdgeApp
//

import Foundation

struct Conversation: Codable, Identifiable, Equatable {
    let id: UUID
    var title: String
    var summary: String?
    var modelName: String
    var updatedAt: Date
    
    init(id: UUID = UUID(), title: String = "New Conversation", summary: String? = nil, modelName: String, updatedAt: Date = Date()) {
        self.id = id
        self.title = title
        self.summary = summary
        self.modelName = modelName
        self.updatedAt = updatedAt
    }
}
