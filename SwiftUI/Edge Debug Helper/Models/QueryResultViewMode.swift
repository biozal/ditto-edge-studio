//
//  QueryResultViewMode.swift
//  Edge Studio
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
