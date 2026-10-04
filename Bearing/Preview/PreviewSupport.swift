#if DEBUG
import SwiftData
import SwiftUI

@MainActor
private func previewContainer() -> ModelContainer {
    let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: Schema(BearingSchema.models), configurations: [configuration])
    DemoContent.seedIfNeeded(in: container.mainContext)
    return container
}

#Preview("Bearing — iPhone") {
    AppRootView()
        .modelContainer(previewContainer())
}

#Preview("Universal Capture") {
    CaptureView()
        .modelContainer(previewContainer())
}
#endif
