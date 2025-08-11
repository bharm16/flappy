//
//  ContentView.swift
//  flappy
//
//  Created by Bryce Harmon on 8/10/25.
//

import SwiftUI
import SpriteKit

struct ContentView: View {
    @State private var scene = GameScene(size: .zero)

    var body: some View {
        GeometryReader { proxy in
            SpriteView(scene: scene)
                .ignoresSafeArea()
                .onAppear {
                    scene.size = proxy.size
                    scene.scaleMode = SKSceneScaleMode.resizeFill
                }
                .onChange(of: proxy.size) { newSize in
                    scene.size = newSize
                }
        }
    }
}
