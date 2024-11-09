//
//  ContentView.swift
//  TempoDetector
//
//  Created by Andrew Higbee on 11/8/24.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var audioProcessor = TempoDetector()
    @State private var isListening = false
    
    var body: some View {
        VStack {
//            Text("Detected Tempo: \(Int(audioProcessor.)) BPM")
//                .font(.largeTitle)
//                .padding()
            
            Button(action: {
                isListening.toggle()
                if isListening {
                    audioProcessor.startListening()
                } else {
                    audioProcessor.stopListening()
                }
            }) {
                Text(isListening ? "Stop Listening" : "Start Listening")
                    .padding()
                    .background(isListening ? Color.red : Color.green)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }
        }
    }
}

#Preview {
    ContentView()
}
