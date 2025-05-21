//
//  ClosedRange+Extensions.swift
//  MTAudioTap
//
//  Created by Alexey Vorobyov on 29.05.2025.
//

extension Comparable {
    func clamped(to limits: ClosedRange<Self>) -> Self {
        min(max(self, limits.lowerBound), limits.upperBound)
    }
}
