//
//  ModelRegistery+custom.swift
//  AIEdgeApp
//
//  Created by Jérôme Pitault on 28.12.2025.
//

import MLXLLM
import MLXLMCommon

extension AbstractModelRegistry {
    static let deepSeekR1_1_5B_4bit = ModelConfiguration(
        id: "mlx-community/DeepSeek-R1-Distill-Qwen-1.5B-4bit",
        overrideTokenizer: "PreTrainedTokenizer",
        defaultPrompt: "List five interesting facts about black holes."
    )
    
    static let qwen2_5Coder_1_5B_4bit = ModelConfiguration(
        id: "mlx-community/Qwen2.5-Coder-1.5B-Instruct-4bit",
        overrideTokenizer: "PreTrainedTokenizer",
        defaultPrompt: "Generate a simple HTTP server in Python."
    )
    
    static let qwen2_VL_2B_Instruct_4bit = ModelConfiguration(
        id: "mlx-community/Qwen2-VL-2B-Instruct-4bit",
        overrideTokenizer: "PreTrainedTokenizer",
        defaultPrompt: "Generate a simple HTTP server in Python."
    )
    
    static let granite_4_0_h_micro_4bit = ModelConfiguration(
        id: "mlx-community/Granite-4.0-h-micro-4bit",
        overrideTokenizer: "PreTrainedTokenizer",
        defaultPrompt: "List five interesting facts about black holes"
    )
    
    static let qwen3_4B_4bit = ModelConfiguration(
        id: "mlx-community/Qwen3-4B-4bit",
        overrideTokenizer: "PreTrainedTokenizer",
        defaultPrompt: "List five interesting facts about black holes"
    )
    
    static let Qwen3_8B_MLX_4bit = ModelConfiguration(
        id: "lmstudio-community/Qwen3-8B-MLX-4bit",
        overrideTokenizer: "PreTrainedTokenizer",
        defaultPrompt: "List five interesting facts about black holes"
    )
    
    static let Qwen3_14B_MLX_4bit = ModelConfiguration(
        id: "lmstudio-community/Qwen3-14B-MLX-4bit",
        overrideTokenizer: "PreTrainedTokenizer",
        defaultPrompt: "List five interesting facts about black holes"
    )
    
    static let Qwen3_5_9B_4bit = ModelConfiguration(
        id: "mlx-community/Qwen3.5-9B-4bit",
        overrideTokenizer: "PreTrainedTokenizer",
        defaultPrompt: "List five interesting facts about black holes"
    )
    
    static let Devstral_Small_2507_MLX_4bit = ModelConfiguration(
        id: "lmstudio-community/Devstral-Small-2507-MLX-4bit",
        overrideTokenizer: "PreTrainedTokenizer",
        defaultPrompt: "List five interesting facts about black holes"
    )
    
    static let Apertus_8B_2509_4bit = ModelConfiguration(
        id: "mlx-community/Apertus-8B-2509-4bit",
        overrideTokenizer: "PreTrainedTokenizer",
        defaultPrompt: "List five interesting facts about black holes"
    )
    
    static let ministral3_3B_4bit = ModelConfiguration(
        id: "mlx-community/Ministral-3-3B-Reasoning-2512-4bit",
        overrideTokenizer: "PreTrainedTokenizer",
        defaultPrompt: "List five interesting facts about black holes"
    )
    
    static let Voxtral_Mini_3B_2507_bf16 = ModelConfiguration(
        id: "mlx-community/Voxtral-Mini-3B-2507-bf16",
        overrideTokenizer: "PreTrainedTokenizer",
        defaultPrompt: "List five interesting facts about black holes"
    )
    
    static let Qwen3_VL_4B_Instruct_3bit  = ModelConfiguration(
        id: "mlx-community/Qwen3-VL-4B-Instruct-3bit",
        overrideTokenizer: "PreTrainedTokenizer",
        defaultPrompt: "List five interesting facts about black holes"
    )
    
    static let gemma_3n_E4B_it_lm_4bit  = ModelConfiguration(
        id: "mlx-community/gemma-3n-E4B-it-lm-4bit",
        overrideTokenizer: "PreTrainedTokenizer",
        defaultPrompt: "List five interesting facts about black holes"
    )
    
    func registerCustomModels() {
        register(configurations: [
            Self.deepSeekR1_1_5B_4bit,
            Self.qwen2_5Coder_1_5B_4bit,
            Self.granite_4_0_h_micro_4bit,
            Self.qwen3_4B_4bit,
            Self.Qwen3_8B_MLX_4bit,
            Self.Qwen3_14B_MLX_4bit,
            Self.Qwen3_5_9B_4bit,
            // Self.Apertus_8B_2509_4bit,
            //Self.qwen2_VL_2B_Instruct_4bit,
            Self.ministral3_3B_4bit,
            Self.gemma_3n_E4B_it_lm_4bit
            //Self.Voxtral_Mini_3B_2507_bf16
        ])
    }
}
