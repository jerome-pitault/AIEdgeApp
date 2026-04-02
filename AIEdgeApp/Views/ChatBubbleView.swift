//
//  ChatBubbleView.swift
//  AIEdgeApp
//
//  Created by Jérôme Pitault on 28.12.2025.
//

import SwiftUI

struct ChatBubbleView: View {
    let bubble: ChatBubble
    var isSpeaking: Bool = false
    var onSpeak: (() -> Void)? = nil
    
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
                            .textSelection(.enabled)
                        
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
                if let onSpeak = onSpeak {
                    Button(action: onSpeak) {
                        Image(systemName: isSpeaking ? "stop.circle.fill" : "speaker.wave.2.circle")
                            .symbolEffect(.pulse, isActive: isSpeaking)
                            .foregroundStyle(isSpeaking ? .red : .blue)
                            .font(.system(size: 24))
                    }
                    .buttonStyle(.plain)
                    .padding(.leading, 4)
                }
                Spacer()
            }
        }
        .id(bubble.id)
    }
}
