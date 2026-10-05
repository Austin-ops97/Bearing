#if DEBUG
import SwiftData
import SwiftUI

@MainActor
private func previewContainer() -> ModelContainer {
    let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: Schema(CailynSchema.models), configurations: [configuration])
    DemoContent.seedIfNeeded(in: container.mainContext)
    return container
}

#Preview("Cailyn — iPhone") {
    AppRootView()
        .modelContainer(previewContainer())
        .environmentObject(VoiceEngine())
}

#Preview("Universal Capture") {
    CaptureView()
        .modelContainer(previewContainer())
        .environmentObject(VoiceEngine())
}
#endif
