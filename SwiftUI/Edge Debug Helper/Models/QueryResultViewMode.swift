//
//  QueryResultViewMode.swift
//  Edge Studio
//
//  Created by Claude Code on 10/2/25.
//

import Foundation

enum QueryResultViewMode: String, CaseIterable, Identifiable {
    case raw = "Raw"
    case table = "Table"
    case map = "Map"

    var id: String { rawValue }

    var iconName: String {
        switch self {
        case .table: return "tablecells"
        case .raw: return "doc.text"
        case .map: return "map"
        }
    }
}
