//
//  ErrorView.swift
//  AIEdgeApp
//
//  Created by Jérôme Pitault on 28.12.2025.
//

import SwiftUI

struct AppErrorView: View {
    let errorMessage: String
    
    @State private var isShowingError = false
    
    var body: some View {
        Button {
            isShowingError = true
        } label: {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(.red)
        }
        .popover(isPresented: $isShowingError, arrowEdge: .bottom) {
            Text(errorMessage)
                .padding()
        }
    }
}

#Preview {
    AppErrorView(errorMessage: "Something went wrong!")
}
