//
//  Item.swift
//  Eye Break
//
//  Created by Flynn on 22/6/26.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
