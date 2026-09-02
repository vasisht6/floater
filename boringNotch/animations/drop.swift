//
//  drop.swift
//  boringNotch
//
//  Created by Harsh Vardhan  Goswami  on  04/08/24.
//

import Foundation
import SwiftUI


public class BoringAnimations {
    @Published var notchStyle: Style = .notch
    
    init() {
        self.notchStyle = .notch
    }
    
    var animation: Animation {
        // Keep the shared fallback aligned with the measured open transition.
        Animation.spring(response: 0.38, dampingFraction: 0.60, blendDuration: 0)
    }
    
    // TODO: Move all animations to this file
    
}
