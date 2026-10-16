import SwiftUI
import UIKit

/// The player card as a system sheet presented from UIKit, so that the sheet's one detent can follow the card's content
/// and change size smoothly. SwiftUI's own `presentationDetents` snaps between heights, and UIKit's `animateChanges`
/// animates the sheet's frame on its own clock while SwiftUI lays the content out at the new size at once, so the
/// controls jump. Here a resize is stepped by hand: on every frame the detent height and the content's scroll offset
/// move together, so the card's top edge slides while the controls stay exactly where they are. The sheet is never
/// taller than the system's largest detent; when the content is taller than that, the content scrolls inside it.
struct CardSheet<Content: View>: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    let cornerRadius: CGFloat
    @ViewBuilder let content: () -> Content

    private static var detentID: UISheetPresentationController.Detent.Identifier { .init("playaway.card.content") }

    func makeCoordinator() -> Coordinator { Coordinator(isPresented: $isPresented) }

    /// The anchor is an empty, untouchable controller: it exists only to present from. A UIKit view in the overlay
    /// would otherwise swallow every tap meant for the list beneath.
    func makeUIViewController(context: Context) -> UIViewController {
        let anchor = UIViewController()
        anchor.view.isUserInteractionEnabled = false
        anchor.view.backgroundColor = .clear
        return anchor
    }

    func updateUIViewController(_ anchor: UIViewController, context: Context) {
        let coordinator = context.coordinator
        coordinator.isPresented = $isPresented
        if isPresented, coordinator.host == nil {
            let host = UIHostingController(rootView: AnyView(content()
                .environment(\.reportCardContentHeight, { [weak coordinator] height in coordinator?.contentHeightChanged(height) })
                .environmentObject(coordinator.resize)))
            host.modalPresentationStyle = .pageSheet
            host.presentationController?.delegate = coordinator
            if let sheet = host.sheetPresentationController {
                sheet.detents = [.custom(identifier: Self.detentID) { [weak coordinator] context in
                    coordinator?.maximumHeight = context.maximumDetentValue
                    return coordinator?.currentHeight(cap: context.maximumDetentValue) ?? Chrome.firstCardHeight
                }]
                sheet.prefersGrabberVisible = false                  // the card draws its own handle
                sheet.preferredCornerRadius = cornerRadius
                sheet.prefersScrollingExpandsWhenScrolledToEdge = false
            }
            coordinator.host = host
            DispatchQueue.main.async { anchor.present(host, animated: true) }
        } else if !isPresented, let host = coordinator.host {
            coordinator.closed()
            host.dismiss(animated: true)
        }
    }

    final class Coordinator: NSObject, UIAdaptivePresentationControllerDelegate {
        var isPresented: Binding<Bool>
        var host: UIHostingController<AnyView>?
        /// The content's own height, as the card last measured it.
        private(set) var contentHeight: CGFloat = 0
        /// The tallest the system lets the sheet be, learnt when the detent is resolved.
        var maximumHeight: CGFloat = .infinity
        /// The sheet's height on the way from one content height to the next; nil when at rest.
        private var animatedHeight: CGFloat?
        private var resizeFrom: CGFloat = 0
        private var resizeTo: CGFloat = 0
        private var resizeStart: CFTimeInterval = 0
        private var link: CADisplayLink?
        /// The shift the card applies to its content during a resize, so the controls stay put on screen.
        let resize = CardResize()

        init(isPresented: Binding<Bool>) { self.isPresented = isPresented }

        func currentHeight(cap: CGFloat) -> CGFloat {
            animatedHeight ?? min(contentHeight > 0 ? contentHeight : Chrome.firstCardHeight, cap)
        }

        /// The card measured its content. The first measurement sizes the sheet as it appears. Later ones (artwork
        /// arriving or going, the lyrics panel changing state) start a stepped resize of the sheet's top edge.
        func contentHeightChanged(_ height: CGFloat) {
            guard height > 0, abs(height - contentHeight) > 0.5 else { return }
            let previous = contentHeight
            contentHeight = height
            guard let host, let sheet = host.sheetPresentationController else { return }
            if previous == 0 || UIAccessibility.isReduceMotionEnabled { stopResize(); sheet.invalidateDetents(); return }
            let from = animatedHeight ?? min(previous, maximumHeight)
            let to = min(height, maximumHeight)
            guard abs(to - from) > 0.5 else { return }
            resizeFrom = from
            resizeTo = to
            resizeStart = CACurrentMediaTime()
            link?.invalidate()
            let link = CADisplayLink(target: self, selector: #selector(step(_:)))
            link.add(to: .main, forMode: .common)
            self.link = link
            step(link)
        }

        /// One frame of a resize: the detent moves along an ease-in-out curve, and the content is shifted by the distance
        /// still to go, so what sits below the change (the controls) does not move on screen. SwiftUI has already laid
        /// the content out at its final height; only the window onto it moves. (A scroll offset cannot do this: it is
        /// clamped whenever the content fits.)
        @objc private func step(_ link: CADisplayLink) {
            guard let host, let sheet = host.sheetPresentationController else { stopResize(); return }
            let progress = min((CACurrentMediaTime() - resizeStart) / Self.resizeDuration, 1)
            let eased = progress < 0.5 ? 2 * progress * progress : 1 - pow(-2 * progress + 2, 2) / 2
            let height = resizeFrom + (resizeTo - resizeFrom) * eased
            animatedHeight = height
            resize.shift = height - resizeTo
            sheet.invalidateDetents()
            if progress >= 1 { stopResize() }
        }

        private func stopResize() {
            link?.invalidate()
            link = nil
            animatedHeight = nil
            resize.shift = 0
        }

        /// How long a resize takes. Ten times longer under the test hook, so a test can watch it frame by frame.
        private static var resizeDuration: CFTimeInterval {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-PlayawaySlowAnimations") { return Chrome.cardResizeDuration * 10 }
            #endif
            return Chrome.cardResizeDuration
        }

        func closed() {
            stopResize()
            host = nil
            contentHeight = 0
        }

        func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
            closed()
            isPresented.wrappedValue = false
        }
    }
}

/// How far the card's content is shifted during a resize; zero at rest.
final class CardResize: ObservableObject {
    @Published var shift: CGFloat = 0
}

private struct ReportCardContentHeightKey: EnvironmentKey {
    static let defaultValue: (CGFloat) -> Void = { _ in }
}

extension EnvironmentValues {
    /// How the card tells its sheet how tall its content is.
    var reportCardContentHeight: (CGFloat) -> Void {
        get { self[ReportCardContentHeightKey.self] }
        set { self[ReportCardContentHeightKey.self] = newValue }
    }
}
