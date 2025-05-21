//
//  MediaPlayerView.swift
//  MTAudioTap
//
//  Created by Alexey Vorobyov on 21.05.2025.
//

import SwiftUI

struct MediaPlayerView: View {
    @State var viewModel = MediaPlayerViewModel()
    var body: some View {
        VStack {
            AudioSpectra(spectra: viewModel.spectra)
                .frame(height: 300)
                .background(Color.gray.tertiary)

            Text("palaying:  \(viewModel.isPlaying ? "yes" : "no")")
                .padding(.bottom, 60)
            Button(
                action: {
                    viewModel.play()
                }, label: {
                    Image(systemName: "play.fill")
                        .font(.system(size: 72))
                        .foregroundStyle(.green)
                }
            )
        }
        .padding()
    }
}

#Preview {
    MediaPlayerView()
}
