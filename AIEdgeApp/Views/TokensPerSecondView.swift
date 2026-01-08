//
//  TokensPerSecondView.swift
//  AIEdgeApp
//
//  Created by Jérôme Pitault on 28.12.2025.
//

import SwiftUI

struct TokensPerSecondView: View {
    let value: Double
    let memoryStats: String

    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text("\(value, format: .number.precision(.fractionLength(2))) t/s")
                .font(.footnote)
                .bold()
            
            Text(memoryStats)
                .font(.caption2)
        }
        .foregroundStyle(.secondary)
    }
    }


#Preview {
    TokensPerSecondView(value: 58.5834, memoryStats: "Used: 156 MB | Ref: 5.90 GB")
}
