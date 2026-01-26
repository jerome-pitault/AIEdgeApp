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

struct ContentView: View {
    /// All models you want to expose in the list
    private let availableModels: [ModelConfiguration] = [
        LLMRegistry.deepSeekR1_1_5B_4bit,
        LLMRegistry.qwen2_5Coder_1_5B_4bit,
        MLXVLM.VLMRegistry.qwen2_VL_2B_Instruct_4bit,
        MLXVLM.VLMRegistry.Qwen3_VL_4B_Instruct_3bit,
        //LLMRegistry.qwen2_VL_2B_Instruct_4bit,
        LLMRegistry.qwen3_4B_4bit,
        LLMRegistry.Qwen3_8B_MLX_4bit,
        LLMRegistry.granite_4_0_h_micro_4bit,
        //LLMRegistry.Apertus_8B_2509_4bit,
        LLMRegistry.ministral3_3B_4bit,
        LLMRegistry.gemma_3n_E4B_it_lm_4bit
        //LLMRegistry.Voxtral_Mini_3B_2507_bf16
    ]

    @State private var showingSettings = false
    @State private var vmForSettings: MLXViewModel? // Temporary VM just for settings adjustments if needed

    init() {
        // Register custom models once
        LLMModelFactory.shared.modelRegistry.registerCustomModels()
        
        // We create a dummy VM just to pass to settings if it requires one for binding.
        // If ModelSettingsView requires a running VM, we might need to adjust it.
        // Assuming for now we can pass a dummy one or refactor ModelSettingsView later if needed.
        _vmForSettings = State(initialValue: MLXViewModel(modelConfiguration: LLMRegistry.qwen3_4B_4bit))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(availableModels, id: \.name) { model in
                        NavigationLink(destination: ChatView(modelConfiguration: model)) {
                            ModelRow(model: model, isSelected: false)
                        }
                        .buttonStyle(.plain)
                        .padding(.vertical, 8) // Tighter spacing
                        .padding(.horizontal)
                        
                        Divider()
                            .padding(.leading, 70) // Indent divider to align with text
                    }
                }
                .padding(.vertical, 8)
            }
            .navigationTitle("Models")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingSettings = true
                    } label: {
                        Image(systemName: "gearshape.fill")
                    }
                }
            }
            .sheet(isPresented: $showingSettings) {
                // Pass the dummy VM or modify SettingsView to not need it if possible.
                // For now, keeping compatibility.
                if let vm = vmForSettings {
                    ModelSettingsView(baseViewModel: vm, availableModels: availableModels)
                }
            }
        }
    }
}

#Preview {
    ContentView()
}

