import SwiftUI

/// Lets the user position/size the crop instead of always cropping the photo's center.
///
/// Fixed ratios (1:1 / 4:5 / 16:9) show a fixed-size frame; the photo is dragged and pinch-zoomed
/// behind it, like Instagram's story crop. "自由" (free) instead shows the whole photo and a
/// resizable frame with corner handles, since there's no ratio to preserve while zooming.
///
/// All geometry is tracked as `NormalizedRect` — a fraction of the photo, the same convention
/// `ImageProcessor.resolvedCropRect` uses for the export — so this preview and the saved photo
/// always agree.
struct CropEditorView: View {
    let photo: UIImage
    var onCancel: () -> Void
    var onConfirm: (CropRatio, NormalizedRect) -> Void

    @State private var ratio: CropRatio
    @State private var selection: NormalizedRect
    @State private var gestureStart: NormalizedRect?

    private static let ratios: [CropRatio] = [.square, .portrait, .wide, .free]
    private let minFraction = 0.12

    init(photo: UIImage, ratio: CropRatio?, rect: NormalizedRect?, onCancel: @escaping () -> Void, onConfirm: @escaping (CropRatio, NormalizedRect) -> Void) {
        self.photo = photo
        self.onCancel = onCancel
        self.onConfirm = onConfirm
        let start = ratio ?? .square
        _ratio = State(initialValue: start)
        _selection = State(initialValue: (rect ?? ImageProcessor.defaultCropRect(ratio: start, extentSize: photo.size)).clamped())
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Picker("比率", selection: Binding(get: { ratio }, set: { setRatio($0) })) {
                    ForEach(Self.ratios, id: \.self) { Text($0.title).tag($0) }
                }.pickerStyle(.segmented).padding(.horizontal, 20).accessibilityIdentifier("cropRatioPicker")
                GeometryReader { geometry in
                    let available = CGSize(width: max(1, geometry.size.width - 32), height: max(1, geometry.size.height - 16))
                    (ratio == .free ? AnyView(freeCanvas(available: available)) : AnyView(fixedCanvas(available: available)))
                        .frame(width: geometry.size.width, height: geometry.size.height)
                }.padding(.horizontal, 16)
                Text(ratio == .free ? "フチをドラッグして範囲を、内側をドラッグして位置を調整できます。" : "ドラッグで位置、ピンチで範囲を調整できます。")
                    .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(.horizontal, 20)
                Button("リセット") { selection = ImageProcessor.defaultCropRect(ratio: ratio, extentSize: photo.size) }
                    .accessibilityIdentifier("cropReset")
            }
            .padding(.top, 8).padding(.bottom, 12)
            .background(Palette.paper).foregroundStyle(Palette.ink).tint(Palette.accent)
            .navigationTitle("トリミング").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("キャンセル") { onCancel() }.accessibilityIdentifier("cropCancel") }
                ToolbarItem(placement: .confirmationAction) { Button("確定") { onConfirm(ratio, selection.clamped()) }.accessibilityIdentifier("cropConfirm") }
            }
        }
    }

    // MARK: Fixed ratio: fixed frame, pan/zoom the photo behind it.

    @ViewBuilder private func fixedCanvas(available: CGSize) -> some View {
        let frame = frameSize(for: ratio, in: available)
        let dispWidth = frame.width / max(selection.width, 0.001)
        let dispHeight = frame.height / max(selection.height, 0.001)
        let offsetX = (0.5 - (selection.x + selection.width / 2)) * dispWidth
        let offsetY = (0.5 - (selection.y + selection.height / 2)) * dispHeight
        ZStack {
            Color.black.opacity(0.85)
            Image(uiImage: photo).resizable().frame(width: dispWidth, height: dispHeight).offset(x: offsetX, y: offsetY).opacity(0.3)
            Image(uiImage: photo).resizable().frame(width: dispWidth, height: dispHeight).offset(x: offsetX, y: offsetY)
                .frame(width: frame.width, height: frame.height).clipped()
                .overlay(RoundedRectangle(cornerRadius: 2).stroke(.white, lineWidth: 2))
        }
        .frame(width: available.width, height: available.height)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier("cropCanvas")
        .gesture(SimultaneousGesture(DragGesture(minimumDistance: 1), MagnificationGesture()).onChanged { value in
            let start = gestureStart ?? selection
            if gestureStart == nil { gestureStart = start }
            var next = start
            if let magnification = value.second { next = zoomed(start, by: magnification) }
            if let drag = value.first {
                next.x = start.x - drag.translation.width * start.width / frame.width
                next.y = start.y - drag.translation.height * start.height / frame.height
            }
            selection = next.clamped()
        }.onEnded { _ in gestureStart = nil })
    }

    private func zoomed(_ base: NormalizedRect, by magnification: CGFloat) -> NormalizedRect {
        guard let value = ratio.fixedValue else { return base }
        let maxWidth = min(1, value)
        let width = min(maxWidth, max(minFraction, base.width / max(magnification, 0.05)))
        let height = width / value
        let centerX = base.x + base.width / 2, centerY = base.y + base.height / 2
        return NormalizedRect(x: centerX - width / 2, y: centerY - height / 2, width: width, height: height)
    }

    private func frameSize(for ratio: CropRatio, in available: CGSize) -> CGSize {
        guard let value = ratio.fixedValue else { return available }
        if available.width / available.height > value {
            return CGSize(width: available.height * value, height: available.height)
        }
        return CGSize(width: available.width, height: available.width / value)
    }

    private func setRatio(_ new: CropRatio) {
        if let value = new.fixedValue {
            let centerX = selection.x + selection.width / 2, centerY = selection.y + selection.height / 2
            let width = min(1, value), height = width / value
            selection = NormalizedRect(x: centerX - width / 2, y: centerY - height / 2, width: width, height: height).clamped()
        }
        ratio = new
    }

    // MARK: Free ratio: whole photo visible, drag the frame and its corner handles.

    private enum Corner: String, CaseIterable {
        case topLeft, topRight, bottomLeft, bottomRight
        func point(in rect: CGRect) -> CGPoint {
            switch self {
            case .topLeft: return CGPoint(x: rect.minX, y: rect.minY)
            case .topRight: return CGPoint(x: rect.maxX, y: rect.minY)
            case .bottomLeft: return CGPoint(x: rect.minX, y: rect.maxY)
            case .bottomRight: return CGPoint(x: rect.maxX, y: rect.maxY)
            }
        }
        func resized(from base: NormalizedRect, translation: CGSize, dispSize: CGSize, minFraction: Double) -> NormalizedRect {
            var rect = base
            let dx = translation.width / dispSize.width, dy = translation.height / dispSize.height
            switch self {
            case .topLeft:
                let x = min(max(base.x + dx, 0), base.x + base.width - minFraction)
                let y = min(max(base.y + dy, 0), base.y + base.height - minFraction)
                rect.width = base.width + (base.x - x); rect.height = base.height + (base.y - y); rect.x = x; rect.y = y
            case .topRight:
                let right = min(max(base.x + base.width + dx, base.x + minFraction), 1)
                let y = min(max(base.y + dy, 0), base.y + base.height - minFraction)
                rect.width = right - base.x; rect.height = base.height + (base.y - y); rect.y = y
            case .bottomLeft:
                let x = min(max(base.x + dx, 0), base.x + base.width - minFraction)
                let bottom = min(max(base.y + base.height + dy, base.y + minFraction), 1)
                rect.width = base.width + (base.x - x); rect.height = bottom - base.y; rect.x = x
            case .bottomRight:
                let right = min(max(base.x + base.width + dx, base.x + minFraction), 1)
                let bottom = min(max(base.y + base.height + dy, base.y + minFraction), 1)
                rect.width = right - base.x; rect.height = bottom - base.y
            }
            return rect
        }
    }

    @ViewBuilder private func freeCanvas(available: CGSize) -> some View {
        let fitScale = min(available.width / max(photo.size.width, 1), available.height / max(photo.size.height, 1))
        let dispSize = CGSize(width: photo.size.width * fitScale, height: photo.size.height * fitScale)
        let rectFrame = CGRect(x: selection.x * dispSize.width, y: selection.y * dispSize.height,
                               width: selection.width * dispSize.width, height: selection.height * dispSize.height)
        ZStack {
            Color.black.opacity(0.85)
            ZStack {
                Image(uiImage: photo).resizable().frame(width: dispSize.width, height: dispSize.height)
                Color.black.opacity(0.55).frame(width: dispSize.width, height: dispSize.height)
                    .mask(Rectangle().overlay(
                        Rectangle().frame(width: rectFrame.width, height: rectFrame.height)
                            .position(x: rectFrame.midX, y: rectFrame.midY).blendMode(.destinationOut)
                    ).compositingGroup())
                Rectangle().stroke(.white, lineWidth: 2).frame(width: rectFrame.width, height: rectFrame.height)
                    .contentShape(Rectangle())
                    .position(x: rectFrame.midX, y: rectFrame.midY)
                    .accessibilityElement(children: .ignore)
                    .accessibilityIdentifier("cropCanvas")
                    .gesture(DragGesture(minimumDistance: 1).onChanged { value in
                        let start = gestureStart ?? selection
                        if gestureStart == nil { gestureStart = start }
                        var next = start
                        next.x = start.x + value.translation.width / dispSize.width
                        next.y = start.y + value.translation.height / dispSize.height
                        next.x = min(max(next.x, 0), 1 - next.width); next.y = min(max(next.y, 0), 1 - next.height)
                        selection = next
                    }.onEnded { _ in gestureStart = nil })
                ForEach(Corner.allCases, id: \.self) { corner in
                    Circle().fill(.white).frame(width: 20, height: 20)
                        .shadow(radius: 1)
                        .position(corner.point(in: rectFrame))
                        .accessibilityIdentifier("cropHandle-\(corner.rawValue)")
                        .gesture(DragGesture(minimumDistance: 1).onChanged { value in
                            let start = gestureStart ?? selection
                            if gestureStart == nil { gestureStart = start }
                            selection = corner.resized(from: start, translation: value.translation, dispSize: dispSize, minFraction: minFraction)
                        }.onEnded { _ in gestureStart = nil })
                }
            }.frame(width: dispSize.width, height: dispSize.height)
        }
        .frame(width: available.width, height: available.height)
    }
}
