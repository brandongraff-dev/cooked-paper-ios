import UIKit

/// apple-design §13: causality, harmony, utility — fire on the actual causal event,
/// on the same frame as the visual change, and only where feedback earns its place.
/// Reserved here for genuinely meaningful moments: a filled trade, an error, a
/// confirmed purchase. Never on routine navigation or a value merely changing.
enum Haptics {
    /// The correct feedback for moving between discrete options — a feed tab, a
    /// timeframe, a quick-amount chip. Distinct from `tap()`: `UISelectionFeedback
    /// Generator` is Apple's own generator for exactly this case (a picker/segment
    /// changing), lighter and more precise than treating it as a generic impact.
    static func selection() {
        UISelectionFeedbackGenerator().selectionChanged()
    }

    static func tap() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    static func commit() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    static func warning() {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }

    static func error() {
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }
}
