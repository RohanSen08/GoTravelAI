//
//  TripPlannerAppApp.swift
//  TripPlannerApp
//
//  Created by Rohan Sen on 4/6/25.
//

import SwiftUI

@main
struct TripPlannerAppApp: App {
    func loadEnv() {
        guard let path = Bundle.main.path(forResource: ".env", ofType: nil) else {
            print("No .env file found")
            return
        }
        
        do {
            let envContents = try String(contentsOfFile: path, encoding: .utf8)
            let envLines = envContents.components(separatedBy: .newlines)
            
            for line in envLines {
                let parts = line.components(separatedBy: "=")
                if parts.count >= 2 {
                    let key = parts[0].trimmingCharacters(in: .whitespaces)
                    let value = parts[1].trimmingCharacters(in: .whitespaces)
                    setenv(key, value, 1)
                }
            }
        } catch {
            print("Error loading .env file: \(error)")
        }
    }
    var body: some Scene {
        WindowGroup {
            ContentView()
                .onAppear {
                    loadEnv()
                }
        }
    }
}
