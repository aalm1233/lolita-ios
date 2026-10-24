import SwiftUI

/// Keep the button's accessibility/hit frame separate from material extending
/// into the bottom safe area. This also keeps Switch Control activation on target.
struct LolitaEditorSaveBar: View {
    let title: String
    var enabled = true
    let identifier: String
    let action: @MainActor () -> Void
    var body: some View {
        HStack {
            Button(action: action) {
                Text(title).frame(maxWidth: .infinity).padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!enabled)
            .accessibilityIdentifier(identifier)
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(.regularMaterial)
    }
}
