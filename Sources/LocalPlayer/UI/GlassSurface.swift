import PlayawayCore
import AppKit

/// The only place Liquid Glass is created. It hands back the system's own glass material, never a custom blur,
/// gradient or image imitating it. Which surfaces use glass is an open decision, so no window uses it yet and the
/// app renders with no glass at all.
enum GlassSurface {
    static func wrap(_ content: NSView) -> NSGlassEffectView {
        let glass = NSGlassEffectView()
        glass.contentView = content
        return glass
    }
}
