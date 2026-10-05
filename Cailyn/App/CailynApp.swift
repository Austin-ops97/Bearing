import SwiftData
import SwiftUI
import MSAL

@main
struct CailynApp: App {
    private let container: ModelContainer
    @StateObject private var voice = VoiceEngine()

    init() {
        do {
            let schema = Schema(CailynSchema.models)
            container = try ModelContainer(for: schema)
        } catch {
            fatalError("Unable to create Cailyn's private local store: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            AppRootView()
                .tint(CailynTheme.champagne)
                .environmentObject(voice)
                .onOpenURL { url in
                    _ = MSALPublicClientApplication.handleMSALResponse(url, sourceApplication: nil)
                }
        }
        .modelContainer(container)
    }
}
