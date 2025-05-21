//
//  SpectrumView.swift
//  AudioSpectrum
//
//  Created by Alexey Vorobyov on 21.05.2025.
//

import SwiftUI

struct AudioSpectra: View {
    let size: CGSize
    let spectra: [[Float]]
    let colors: [Color] = [.red, .green, .blue, .yellow]
    var body: some View {
        ZStack {
            ForEach(Array(spectra.enumerated()), id: \.offset) { offset, spectrum in
                AudioSpectrum(
                    size: size,
                    spectrum: spectrum,
                    color: colors[offset % colors.count]
                )
            }
        }
    }
}

struct AudioSpectrum: View {
    let size: CGSize
    let spectrum: [Float]
    let color: Color

    var body: some View {
        let barWidth: CGFloat = spectrum.count > 0
            ? size.width / CGFloat(spectrum.count) : 0

        HStack(alignment: .center, spacing: barWidth - barWidth * 3 / 4) {
            ForEach(Array(spectrum.enumerated()), id: \.offset) { _, value in
                LineView(
                    value: value
                )
                .fill(color.opacity(0.8))
            }
        }
        .frame(width: size.width, height: size.height)
    }
}

struct LineView: Shape {
    let value: Float

    func path(in rect: CGRect) -> Path {
        let cornerRadius = rect.width / 2
        let height = max(rect.width, CGFloat(value.clamped(to: 0 ... 1)) * rect.height)
        let lineRect = CGRect(
            x: 0,
            y: 0 + (rect.height - height) / 2,
            width: rect.width,
            height: height
        )
        return Path(roundedRect: lineRect, cornerRadius: cornerRadius)
    }
}

#Preview {
    AudioSpectra(
        size: .init(width: 300, height: 300),
        spectra: [
            [0.3, 0.8, 0.4, 0.6, 0.0]
        ]
    )
    .background(Color.gray.tertiary)
}
