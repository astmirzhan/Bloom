import SwiftUI

/// Draws the wheel: glass (or material) surfaces from `WheelBackground`,
/// then on top the selection pill, dividers, labels and the caption in the
/// middle (the ring's name and key, what a drop would do, or "Cancel").
/// Hit-testing lives in `RadialGeometry`; this view only paints
/// `RadialMenuModel`'s state.
struct RadialMenuView: View {
    @ObservedObject var model: RadialMenuModel
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// How a sub-ring opens and closes: its glass (WheelBackground) and its
    /// labels share this, so they move as one.
    static func subRingAnimation(reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeOut(duration: 0.12) : .spring(duration: 0.2, bounce: 0.12)
    }

    /// Space between the ring's inner edge and the centre disc.
    static let centerGap: CGFloat = 6
    /// How far the selection pill sits inside its slice.
    static let selectionInset: CGFloat = 4

    private var geometry: RadialGeometry { model.geometry }

    var body: some View {
        ZStack {
            WheelBackground(model: model)
            Canvas { context, size in
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                drawRing(in: &context, center: center)
                drawCenter(in: &context, center: center)
            }
            // Switching rings cross-fades the labels.
            .id(model.mode)
            .transition(.opacity)
            // The sub-ring's labels in a layer of their own, so they grow in
            // with its glass instead of appearing before it.
            if let group = model.openGroup {
                Canvas { context, size in
                    drawSubRing(in: &context, center: CGPoint(x: size.width / 2, y: size.height / 2))
                }
                .id(group)
                .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.94)))
            }
        }
        .animation(Self.subRingAnimation(reduceMotion: reduceMotion), value: model.openGroup)
        .frame(width: geometry.panelSide, height: geometry.panelSide)
        .scaleEffect(model.isPresented || reduceMotion ? 1 : 0.86)
        .opacity(model.isPresented ? 1 : 0)
        .animation(reduceMotion ? .easeOut(duration: 0.12) : .spring(duration: 0.3, bounce: 0.22), value: model.isPresented)
        .animation(.easeInOut(duration: 0.16), value: model.mode)
        .accessibilityElement()
        .accessibilityLabel("\(model.mode.title) wheel")
        .accessibilityValue(model.caption.title)
    }

    // MARK: - Colours

    private var highlight: Color {
        model.theme == .petals ? model.accent.color : .accentColor
    }
    /// A petal at rest: near-solid white on the grey glass (a
    /// dark grey in Dark Mode), so labels read the same on any wallpaper.
    private var petal: Color {
        if colorScheme == .dark { return Color(white: contrast == .increased ? 0.32 : 0.24).opacity(0.9) }
        return .white.opacity(contrast == .increased ? 1 : 0.88)
    }
    private var petalEdge: Color { Color.black.opacity(colorScheme == .dark ? 0.3 : 0.07) }
    /// Each ring's petal type size and labels, keyed by ring, width and
    /// titles: measuring text is slow, and the ring redraws on every hover.
    @MainActor private static var petalLabels: [String: (size: CGFloat, labels: [String])] = [:]
    /// Liquid Glass petals (macOS 26 and later) rather than painted ones.
    static var glassPetals: Bool {
        if #available(macOS 26.0, *) { return true }
        return false
    }
    private var divider: Color { Color.primary.opacity(contrast == .increased ? 0.35 : 0.12) }
    private var edge: Color { Color.primary.opacity(contrast == .increased ? 0.5 : 0) }

    // MARK: - Ring

    private func drawRing(in context: inout GraphicsContext, center: CGPoint) {
        if contrast == .increased {
            let r = geometry.outerRadius
            context.stroke(Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: 2 * r, height: 2 * r)),
                           with: .color(edge), lineWidth: 1)
        }
        guard model.phase == .ready else { return }
        if model.theme == .petals {
            drawPetals(in: &context, center: center)
            return
        }

        let count = model.slices.count
        let span = geometry.span(count: count)
        let labelRadius = (geometry.innerRadius + geometry.outerRadius) / 2
        for slice in model.slices {
            let mid = geometry.centerAngle(ofSlice: slice.id, count: count)
            let isHit = model.hit == .slice(slice.id)
            let isOpen = model.openGroup == slice.id
            if isHit || isOpen {
                context.fill(selection(center: center, inner: geometry.innerRadius, outer: geometry.outerRadius,
                                       mid: mid, span: span),
                             with: .color(isHit && !slice.isGroup ? highlight : highlight.opacity(0.28)))
            }
            if count > 1 {
                let angle = mid - span / 2
                var line = Path()
                line.move(to: RadialGeometry.viewPoint(angle: angle, radius: geometry.innerRadius + 10, center: center))
                line.addLine(to: RadialGeometry.viewPoint(angle: angle, radius: geometry.outerRadius - 10, center: center))
                context.stroke(line, with: .color(divider), lineWidth: 1)
            }
            drawLabel(slice.title, symbol: slice.symbol, chevron: slice.isGroup,
                      at: RadialGeometry.viewPoint(angle: mid, radius: labelRadius, center: center),
                      width: min(92, CGFloat(span) * labelRadius - 4), onAccent: isHit && !slice.isGroup,
                      fontSize: count > 10 ? 11 : 11.5, in: &context)
        }
    }

    /// Petals: one separate rounded petal per slice, a few points inside
    /// the disc's rim, filled orange under the pointer.
    private func drawPetals(in context: inout GraphicsContext, center: CGPoint) {
        let count = model.slices.count
        let span = geometry.span(count: count)
        let labelRadius = BandShape.petalLabelRadius(geometry)
        let rect = CGRect(x: center.x - geometry.panelSide / 2, y: center.y - geometry.panelSide / 2,
                          width: geometry.panelSide, height: geometry.panelSide)
        // One type size for the whole ring, the largest at which every
        // label's longest word fits its petal, so the labels read as a set.
        let width = min(92, CGFloat(span) * labelRadius - 8)
        // Formats: big extensions. Tools and actions: an icon over a small
        // all-caps caption.
        let captions = model.mode != .formats
        func text(_ slice: RadialMenuModel.Slice) -> String {
            captions ? Self.shortCaption(slice.title).uppercased() : slice.title
        }
        let texts = model.slices.map(text)
        // Spaced-out captions run wider than `fit` measures them.
        let fitWidth = captions ? width - 6 : width
        let key = "\(model.mode.rawValue)|\(fitWidth)|" + texts.joined(separator: "\u{1}")
        let layout: (size: CGFloat, labels: [String])
        if let cached = Self.petalLabels[key] {
            layout = cached
        } else {
            let size = zip(texts, model.slices).map { text, slice in
                Self.fit(text + (slice.isGroup ? " ›" : ""), width: fitWidth, size: captions ? 9 : 14,
                         minimum: captions ? 7.5 : 11, weight: .bold, in: context).size
            }.min() ?? 14
            // A word still too wide at that size is shortened in the middle.
            let labels = texts.map { Self.fit($0, width: fitWidth, size: size, minimum: size, weight: .bold, in: context).string }
            layout = (size, labels)
            if Self.petalLabels.count > 32 { Self.petalLabels.removeAll() }
            Self.petalLabels[key] = layout
        }
        let fontSize = layout.size
        for slice in model.slices {
            let mid = geometry.centerAngle(ofSlice: slice.id, count: count)
            let isHit = model.hit == .slice(slice.id)
            let isOpen = model.openGroup == slice.id
            let shape = BandShape.petal(slice.id, of: count, geometry: geometry).path(in: rect)
            // On macOS 26 resting petals are glass (see WheelBackground).
            // The highlight is always painted: a tint on glass washes a deep
            // colour out to a pale one that white text can't be read on.
            let fill: Color? = isHit && !slice.isGroup ? highlight
                : isHit || isOpen ? highlight.opacity(0.35)
                : Self.glassPetals ? nil : petal
            if let fill { context.fill(shape, with: .color(fill)) }
            context.stroke(shape, with: .color(contrast == .increased ? edge
                                                : Self.glassPetals ? .white.opacity(0.45) : petalEdge), lineWidth: 1)
            // The chevron marks a group: rest on it to open its sub-ring
            // (dropping on the group itself does nothing).
            drawLabel(layout.labels[slice.id], symbol: captions ? slice.symbol : nil, chevron: slice.isGroup,
                      at: RadialGeometry.viewPoint(angle: mid, radius: labelRadius, center: center),
                      width: width, onAccent: isHit && !slice.isGroup, fontSize: fontSize,
                      weight: .bold, tracking: captions ? 0.5 : 0, in: &context)
        }
    }

    /// Captions fit a word or two; these titles are longer.
    static func shortCaption(_ title: String) -> String {
        switch title {
        case "Remove Background": return "Remove BG"
        case "Recognize Text": return "Get Text"
        case "Remove Metadata": return "No Metadata"
        default: return title
        }
    }

    /// What the centre capsule says: the slice under the pointer, else how
    /// many files are being dragged.
    /// Until the files are known, or when the drop would cancel or there's
    /// nothing to offer, it says so: the same words as the Classic caption.
    private var centerLabel: String {
        guard model.phase == .ready, model.hit != .center, !model.slices.isEmpty else { return model.caption.title }
        switch model.hit {
        case .slice(let index) where model.slices.indices.contains(index):
            return model.slices[index].title
        case .subSlice(let index) where model.openGroupMembers.indices.contains(index):
            return model.openGroupMembers[index].title
        default:
            if model.inputs.count > 1 { return "\(model.inputs.count) files" }
            guard model.totalBytes > 0 else { return "1 file" }
            return ByteCountFormatter.string(fromByteCount: model.totalBytes, countStyle: .file)
        }
    }

    /// The Petals centre: the grey glass shows through inside
    /// a thin white ring; a white 70 × 30 capsule just above the middle
    /// names what a drop would do; three dots below it mark the ring.
    private func drawPetalsCenter(in context: inout GraphicsContext, center: CGPoint) {
        let r = geometry.innerRadius - 6
        let well = Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: 2 * r, height: 2 * r))
        if model.hit == .center && model.phase == .ready {
            context.fill(well, with: .color(Color.black.opacity(0.12))) // a drop here cancels
        }
        context.stroke(well, with: .color(contrast == .increased ? edge : Color.white.opacity(0.7)), lineWidth: 1)

        // Wider and two lines for messages ("No formats for this").
        let label = centerLabel
        let wide = label.count > 10
        let pill = CGRect(x: center.x - (wide ? 38 : 35), y: center.y - (wide ? 24 : 18),
                          width: wide ? 76 : 70, height: wide ? 40 : 30)
        context.fill(Path(roundedRect: pill, cornerRadius: wide ? 14 : 15), with: .color(petal))
        context.stroke(Path(roundedRect: pill, cornerRadius: wide ? 14 : 15), with: .color(petalEdge), lineWidth: 1)
        let fitted = Self.fit(label, width: pill.width - 12, size: wide ? 11 : 13, minimum: 9, weight: .semibold, in: context)
        let text = context.resolve(Text(fitted.string).font(.system(size: fitted.size, weight: .semibold))
            .foregroundColor(.primary))
        let size = text.measure(in: CGSize(width: pill.width - 12, height: pill.height))
        context.draw(text, in: CGRect(x: pill.midX - size.width / 2, y: pill.midY - size.height / 2,
                                      width: size.width, height: size.height))
        drawRingDots(in: &context, center: center, y: center.y + 22)
    }

    /// Three dots, one per ring, the current one in the highlight colour.
    private func drawRingDots(in context: inout GraphicsContext, center: CGPoint, y: CGFloat) {
        for (index, mode) in RingMode.wheelOrder.enumerated() {
            let x = center.x + CGFloat(index - 1) * 9
            let dot = Path(ellipseIn: CGRect(x: x - 2.5, y: y, width: 5, height: 5))
            context.fill(dot, with: .color(mode == model.mode ? highlight : Color.secondary.opacity(0.35)))
        }
    }

    /// The rounded pill marking a slice, inset from its edges so its corners
    /// sit concentric with the ring.
    private func selection(center: CGPoint, inner: CGFloat, outer: CGFloat, mid: Double, span: Double) -> Path {
        let inset = Self.selectionInset
        let angularInset = Double(inset / ((inner + outer) / 2))
        return BandShape.path(center: center, inner: inner + inset, outer: outer - inset,
                              from: mid - span / 2 + angularInset, to: mid + span / 2 - angularInset, corner: 12)
    }

    private func drawSubRing(in context: inout GraphicsContext, center: CGPoint) {
        guard let parent = model.openGroup else { return }
        let members = model.openGroupMembers
        let count = model.slices.count
        let span = geometry.subSpan(members: members.count)
        let labelRadius = (geometry.subInnerRadius + geometry.subOuterRadius) / 2
        for (index, member) in members.enumerated() {
            let mid = geometry.subCenterAngle(member: index, members: members.count, parent: parent, count: count)
            let isHit = model.hit == .subSlice(index)
            if isHit {
                context.fill(selection(center: center, inner: geometry.subInnerRadius, outer: geometry.subOuterRadius,
                                       mid: mid, span: span), with: .color(highlight))
            }
            drawLabel(member.title, symbol: nil, chevron: false,
                      at: RadialGeometry.viewPoint(angle: mid, radius: labelRadius, center: center),
                      width: CGFloat(span) * labelRadius - 4, onAccent: isHit, fontSize: 11.5, in: &context)
        }
    }

    // MARK: - Centre

    private func drawCenter(in context: inout GraphicsContext, center: CGPoint) {
        if model.theme == .petals {
            drawPetalsCenter(in: &context, center: center)
            return
        }
        let r = geometry.innerRadius - Self.centerGap
        let disc = Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: 2 * r, height: 2 * r))
        // A quiet well on the glass (a fill, not more glass), darker when a
        // drop here would cancel.
        let cancelling = model.hit == .center && model.phase == .ready
        context.fill(disc, with: .color(Color.primary.opacity(cancelling ? 0.14 : 0.05)))
        context.stroke(disc, with: .color(contrast == .increased ? edge : divider), lineWidth: 1)

        // The ring's name with its key, and dots showing where it sits among the three.
        let keyGlyph = model.ringKeys().key(for: model.mode).map { "\($0.symbol) " } ?? ""
        let ringLabel = context.resolve(Text(keyGlyph + model.mode.title.uppercased())
            .font(.system(size: 8.5, weight: .bold)).tracking(0.8).foregroundColor(.secondary))
        context.draw(ringLabel, at: CGPoint(x: center.x, y: center.y - r + 13))
        drawRingDots(in: &context, center: center, y: center.y + r - 15)

        let caption = model.caption
        let box = CGRect(x: center.x - r + 8, y: center.y - r + 20, width: 2 * r - 16, height: 2 * r - 40)
        let title = Self.fit(caption.title, width: box.width, size: 12, minimum: 9.5, weight: .semibold, in: context)
        var text = Text(title.string).font(.system(size: title.size, weight: .semibold))
        if let detail = caption.detail {
            let fitted = Self.fit(detail, width: box.width, size: 10, minimum: 8.5, weight: .regular, in: context)
            text = text + Text("\n" + fitted.string).font(.system(size: fitted.size)).foregroundColor(.secondary)
        }
        let resolved = context.resolve(text.foregroundColor(.primary))
        let size = resolved.measure(in: box.size)
        context.draw(resolved, in: CGRect(x: box.midX - size.width / 2, y: box.midY - size.height / 2,
                                          width: size.width, height: size.height))
    }

    /// The largest size from `size` down to `minimum` at which every word of
    /// `string` fits `width`, so lines only break between words. A word
    /// that still doesn't fit is shortened in the middle ("IMG_20…41.heic").
    static func fit(_ string: String, width: CGFloat, size: CGFloat, minimum: CGFloat, weight: Font.Weight,
                    in context: GraphicsContext) -> (string: String, size: CGFloat) {
        func wordWidth(_ word: String, _ size: CGFloat) -> CGFloat {
            context.resolve(Text(word).font(.system(size: size, weight: weight)))
                .measure(in: CGSize(width: 2000, height: 100)).width
        }
        func widest(_ text: String, _ size: CGFloat) -> CGFloat {
            text.split(separator: " ").map { wordWidth(String($0), size) }.max() ?? 0
        }
        var size = size
        while size > minimum && widest(string, size) > width { size -= 0.5 }
        guard widest(string, size) > width else { return (string, size) }
        let words = string.split(separator: " ", omittingEmptySubsequences: false).map { word -> String in
            let characters = Array(word)
            guard wordWidth(String(word), size) > width else { return String(word) }
            for removed in 1..<max(characters.count - 2, 2) {
                let kept = characters.count - removed
                let candidate = String(characters.prefix(kept - kept / 2)) + "…" + String(characters.suffix(kept / 2))
                if wordWidth(candidate, size) <= width { return candidate }
            }
            return String(word)
        }
        return (words.joined(separator: " "), size)
    }

    // MARK: - Labels

    /// Draws an optional symbol above a label, centred on `point`. Labels
    /// wrap between words to fit `width`, but never break inside a word.
    private func drawLabel(_ title: String, symbol: String?, chevron: Bool, at point: CGPoint, width: CGFloat,
                           onAccent: Bool, fontSize: CGFloat, weight: Font.Weight = .semibold,
                           tracking: CGFloat = 0, in context: inout GraphicsContext) {
        let color: Color = onAccent ? .white : .primary
        let font = Font.system(size: fontSize, weight: weight)
        func styled(_ string: String, chevron: Bool = false) -> Text {
            var text = Text(string).font(font).tracking(tracking)
            if chevron { text = text + Text(" ›").font(font) }
            return text.foregroundColor(color)
        }
        // Break between words into lines that fit `width`, each centred
        // (a wrapped Text in a Canvas would be left-aligned). The chevron
        // goes on the last line only.
        let unbounded = CGSize(width: 1000, height: 60)
        func measure(_ string: String, chevron: Bool = false) -> CGSize {
            context.resolve(styled(string, chevron: chevron)).measure(in: unbounded)
        }
        var lines: [String] = []
        for word in title.split(separator: " ").map(String.init) {
            if let last = lines.last, measure(last + " " + word).width <= width {
                lines[lines.count - 1] = last + " " + word
            } else {
                lines.append(word)
            }
        }
        let lineSizes = lines.indices.map { measure(lines[$0], chevron: chevron && $0 == lines.count - 1) }
        let size = CGSize(width: lineSizes.map(\.width).max() ?? 0, height: lineSizes.map(\.height).reduce(0, +))

        var top = point.y - size.height / 2
        if let symbol {
            var image = context.resolve(Image(systemName: symbol))
            image.shading = .color(color)
            let gap: CGFloat = 3
            top = point.y - (image.size.height + gap + size.height) / 2
            context.draw(image, at: CGPoint(x: point.x, y: top + image.size.height / 2))
            top += image.size.height + gap
        }
        for (index, (line, lineSize)) in zip(lines, lineSizes).enumerated() {
            let text = styled(line, chevron: chevron && index == lines.count - 1)
            context.draw(context.resolve(text), in: CGRect(x: point.x - lineSize.width / 2, y: top,
                                                          width: lineSize.width, height: lineSize.height))
            top += lineSize.height
        }
    }
}
