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

struct ConversationItem: Identifiable {
    let id: UUID
    let name: String
    let url: URL
    let modified: Date
}

struct ContentView: View {
    @State private var conversations: [ConversationItem] = []
    @State private var isLoading: Bool = false

    init() {
        // Performance: Run heavy scans in the background to avoid blocking main thread
        Task.detached(priority: .utility) {
            // Cleanup abandoned downloads in tmp
            AppLogger.clearTemporaryDirectory()
            // Log downloaded models and files at launch
            AppLogger.logDownloadedFiles()
        }
    }

    private var conversationsDirectoryURL: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent("Conversations", isDirectory: true)
    }

    private func loadConversations() {
        if isLoading { return }
        isLoading = true
        defer { isLoading = false }

        let fm = FileManager.default
        let dir = conversationsDirectoryURL

        // Ensure directory exists
        if !fm.fileExists(atPath: dir.path) {
            do {
                try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            } catch {
                print("Failed to create Conversations directory: \(error)")
            }
        }

        do {
            let resourceKeys: [URLResourceKey] = [.contentModificationDateKey, .isDirectoryKey]
            let urls = try fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: resourceKeys, options: [.skipsHiddenFiles])

            var items: [ConversationItem] = []
            for url in urls {
                let values = try url.resourceValues(forKeys: Set(resourceKeys))
                if values.isDirectory == true { continue }
                let modified = values.contentModificationDate ?? .distantPast
                let baseName = url.deletingPathExtension().lastPathComponent
                guard baseName != "index" && baseName != "global_settings" else { continue }
                guard let stableID = UUID(uuidString: baseName) else { continue }
                let item = ConversationItem(id: stableID, name: baseName, url: url, modified: modified)
                items.append(item)
            }

            items.sort { $0.modified > $1.modified }

            DispatchQueue.main.async {
                self.conversations = items
            }
        } catch {
            print("Error loading conversations: \(error)")
            DispatchQueue.main.async {
                self.conversations = []
            }
        }
    }

    var body: some View {
        NavigationStack {
            List(conversations) { item in
                // Adjust ChatView initializer to match your project. This assumes a `conversationURL:` init.
                NavigationLink(destination: {
                    let config = ModelWithRequirement.compatible.first ?? LLMRegistry.deepSeekR1_1_5B_4bit
                    ChatView(modelConfiguration: config, conversationId: item.id)
                }) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.name)
                            .font(.headline)
                        HStack(spacing: 6) {
                            Image(systemName: "clock")
                                .foregroundStyle(.secondary)
                            Text(item.modified, style: .date)
                                .foregroundStyle(.secondary)
                            Text(item.modified, style: .time)
                                .foregroundStyle(.secondary)
                        }
                        .font(.subheadline)
                    }
                    .padding(.vertical, 4)
                }
            }
            .overlay {
                if conversations.isEmpty {
                    ContentUnavailableView("No Conversations", systemImage: "text.bubble", description: Text("Your saved chats will appear here."))
                }
            }
            .navigationTitle("Conversations")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    NavigationLink(destination: {
                        let config = ModelWithRequirement.compatible.first ?? LLMRegistry.deepSeekR1_1_5B_4bit
                        ChatView(modelConfiguration: config, conversationId: nil)
                    }) {
                        Image(systemName: "plus")
                    }
                }
            }
            .refreshable { loadConversations() }
            .onAppear { loadConversations() }
        }
    }
}

#Preview {
    ContentView()
}
