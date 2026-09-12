import SwiftUI

@main
struct SwiftDataRollbackReproApp: App {
  var body: some Scene {
    WindowGroup {
      VStack(spacing: 16) {
        Text("SwiftData Rollback Reproducers")
          .font(.headline)
        Text("Choose Product > Test in Xcode to run the two independent reproducers.")
          .multilineTextAlignment(.center)
      }
      .padding()
    }
  }
}
