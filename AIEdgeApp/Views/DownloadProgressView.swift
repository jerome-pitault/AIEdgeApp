//
//  DownloadProgressView.swift
//  AIEdgeApp
//
//  Created by Jérôme Pitault on 28.12.2025.
//

import SwiftUI

struct DownloadProgressView: View {
    let progress: Progress

    @State private var isShowingDownload = false

    var body: some View {
        Button {
            isShowingDownload = true
        } label: {
            Image(systemName: "arrow.down.circle.fill")
                .foregroundStyle(.tint)
                .symbolEffect(.bounce, options: .repeating)
        }
        .popover(isPresented: $isShowingDownload, arrowEdge: .bottom) {
            VStack {
                ProgressView(value: progress.fractionCompleted) {
                    HStack {
                        Text(progress.localizedAdditionalDescription)
                            .bold()
                        Spacer()
                        Text(progress.localizedDescription)
                    }
                }

                Text("The model is downloading")
                    .padding(.horizontal, 32)
            }
            .padding()
        }
    }
}

#Preview {
    DownloadProgressView(progress: Progress(totalUnitCount: 6))
}
