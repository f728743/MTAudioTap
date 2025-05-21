//
//  SpectrumView.swift
//  AudioSpectrum
//
//  Created by Alexey Vorobyov on 21.05.2025.
//

import SwiftUI

struct AudioSpectra: View {
    let spectra: [[Float]]
    let colors: [Color] = [.red, .green, .blue, .yellow]
    var body: some View {
        ZStack {
            ForEach(Array(spectra.enumerated()), id: \.offset) { offset, spectrum in
                AudioSpectrum(
                    spectrum: spectrum,
                    color: colors[offset % colors.count]
                )
            }
        }
    }
}

struct AudioSpectrum: View {
    let spectrum: [Float]
    let color: Color
    var body: some View {
        HStack(alignment: .center, spacing: 2) {
            ForEach(Array(spectrum.enumerated()), id: \.offset) { _, value in
                LineView(value: value)
                    .fill(color.opacity(0.8))
            }
        }
    }
}

struct LineView: Shape {
    var value: Float
    func path(in rect: CGRect) -> Path {
        let cornerRadius = rect.width / 8
        let height = CGFloat(value) * rect.height
        let lineRect = CGRect(x: 0, y: rect.maxY - height, width: rect.width, height: height)
        return Path(roundedRect: lineRect, cornerRadius: cornerRadius)
    }
}

#Preview {
    AudioSpectra(
        spectra: [
            [1, 0.6, 0.8, 0.3, 0.1],
            [0.8, 0.4, 0.7, 0.6, 0.0]
        ]
    )
}
