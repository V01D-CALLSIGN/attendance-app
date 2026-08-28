//
//  ContentView.swift
//  attendance-app
//
//  Created by Anirban Bagchi on 8/28/26.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var repository = LocalAttendanceRepository()
    var body: some View {
        Group {
            if repository.setupComplete { MainTabView() }
            else { OnboardingFlow() }
        }
        .environmentObject(repository)
        .tint(AppTheme.deep)
        .preferredColorScheme(.light)
    }
}

#Preview { ContentView() }
