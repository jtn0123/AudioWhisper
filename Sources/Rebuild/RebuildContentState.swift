import SwiftUI

/// Empty, working and recovery states share a readable hierarchy on every page.
@MainActor
struct RebuildContentState<Actions: View>: View {
    let title: String
    let symbol: String
    let detail: String
    var busy = false
    @ViewBuilder let actions: Actions

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                if busy {
                    ProgressView().controlSize(.small).accessibilityLabel(title)
                } else {
                    Image(systemName: symbol).foregroundStyle(RebuildTheme.accentText).accessibilityHidden(true)
                }
                Text(title).font(.system(size: 15, weight: .semibold)).accessibilityAddTraits(.isHeader)
            }
            Text(detail).font(.system(size: 12.5)).foregroundStyle(RebuildTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            actions.controlSize(.regular)
        }
        .frame(maxWidth: .infinity, minHeight: 80, alignment: .leading)
        .accessibilityElement(children: .contain)
    }
}

extension RebuildContentState where Actions == EmptyView {
    init(title: String, symbol: String, detail: String, busy: Bool = false) {
        self.init(title: title, symbol: symbol, detail: detail, busy: busy) { EmptyView() }
    }
}

/// Download progress has the same spacing, measured percentage and cancellation
/// affordance for speech and writing models. Indeterminate work stays honest.
@MainActor
struct RebuildDownloadProgress<Actions: View>: View {
    let title: String
    let message: String
    let fraction: Double?
    @ViewBuilder let actions: Actions

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let fraction {
                ProgressView(value: fraction).accessibilityLabel(title)
            } else {
                ProgressView().progressViewStyle(.linear).accessibilityLabel(title)
            }
            HStack(alignment: .top, spacing: 10) {
                Text(message).font(.system(size: 12)).textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                if let fraction {
                    Text(fraction.formatted(.percent.precision(.fractionLength(0))))
                        .font(.system(size: 12)).monospacedDigit().foregroundStyle(RebuildTheme.secondaryText)
                }
                actions
            }
        }
        .padding(12)
        .background(RebuildTheme.surfaceSunken, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
