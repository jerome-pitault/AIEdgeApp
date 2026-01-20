//
//  ChatBubble.swift
//  AIEdgeApp
//
//  Created by AI Agent.
//

import Foundation
import Observation

enum ChatRole: String, Codable {
    case user
    case assistant
    case system // For search results or system messages
}

@Observable
class ChatBubble: Identifiable, Equatable {
    let id = UUID()
    let role: ChatRole
    var content: String
    var isStreaming: Bool
    var images: [Data]?
    
    init(role: ChatRole, content: String, images: [Data]? = nil, isStreaming: Bool = false) {
        self.role = role
        self.content = content
        self.images = images
        self.isStreaming = isStreaming
    }
    
    // For Equatable conformance (identity based)
    static func == (lhs: ChatBubble, rhs: ChatBubble) -> Bool {
        return lhs.id == rhs.id
    }
}
