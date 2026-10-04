import SwiftData
import SwiftUI

@main
struct BearingApp: App {
    private let container: ModelContainer

    init() {
        do {
            let schema = Schema(BearingSchema.models)
            container = try ModelContainer(for: schema)
        } catch {
            fatalError("Unable to create Bearing's private local store: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            AppRootView()
                .tint(BearingTheme.olive)
                .task { DemoContent.seedIfNeeded(in: container.mainContext) }
        }
        .modelContainer(container)
    }
}

