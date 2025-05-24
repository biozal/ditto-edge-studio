//
//  ResultJsonViewer.swift
//  Ditto Edge Studio
//
//  Created by Aaron LaBeau on 5/23/25.
//

import SwiftUI
import CodeEditor

struct ResultJsonViewer : View {
    @Binding var resultText: String
    var body: some View {
        VStack(alignment: .leading) {
            CodeEditor(source: resultText, language: .json, theme: .atelierSavannaDark)
        }
    }
}
