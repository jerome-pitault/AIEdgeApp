//
//  DeviceMemory.swift
//  AIEdgeApp
//
//  Helpers for device RAM and model compatibility.
//

import Foundation
import MLXLLM
import MLXLMCommon
import MLXVLM

/// Returns total physical RAM in gigabytes (rounded down).
/// Works on both iOS and macOS.
var deviceTotalRAMGB: Int {
    let bytes = ProcessInfo.processInfo.physicalMemory
    return Int(bytes / (1024 * 1024 * 1024))
}

/// Models with their minimum RAM requirement (GB).
/// Only models where deviceTotalRAMGB >= minRAMGB are shown.
enum ModelWithRequirement {
    static let all: [(ModelConfiguration, minRAMGB: Int)] = [
        (LLMRegistry.deepSeekR1_1_5B_4bit, 4),
        (LLMRegistry.qwen2_5Coder_1_5B_4bit, 4),
        (MLXVLM.VLMRegistry.qwen2_VL_2B_Instruct_4bit, 4),
        (MLXVLM.VLMRegistry.Qwen3_VL_4B_Instruct_3bit, 6),
        (LLMRegistry.qwen3_4B_4bit, 6),
        (LLMRegistry.Qwen3_8B_MLX_4bit, 7),
        (LLMRegistry.Qwen3_14B_MLX_4bit, 12),
        (LLMRegistry.Qwen3_5_9B_4bit,7),
        (LLMRegistry.Devstral_Small_2507_MLX_4bit,14),
        (LLMRegistry.granite_4_0_h_micro_4bit, 6),
        (LLMRegistry.ministral3_3B_4bit, 5),
        (LLMRegistry.gemma_3n_E4B_it_lm_4bit, 6),
    ]

    /// Models that can run on the current device.
    static var compatible: [ModelConfiguration] {
        let ram = deviceTotalRAMGB
        print("RAM :  \(ram)")
        return all
            .filter { ram >= $0.minRAMGB }
            .map(\.0)
    }
}
