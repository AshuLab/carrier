import CarrierCore
import SwiftUI

/// Asks the engine again without a save, for a refusal that may be gone (the file was fixed by hand); off while an ask is `pending`.
struct AskAgainButton: View {
    let pending: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) { Label(Copy.engineAskAgain(), icon: .refresh) }
            .buttonStyle(SecondaryCapsuleButtonStyle()).controlSize(.small).disabled(pending)
    }
}
