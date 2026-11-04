import SwiftUI

// F-122-F: the Crop tool's canvas. It shows the whole, plain photo with the
// crop frame over it: the outside dimmed, corner and edge handles (44-pt hit
// areas), the frame itself draggable, and a rule-of-thirds grid while a drag
// is under way. Dumb on purpose: it draws the crop it is given and reports
// raw drags in points; PhotoEditViewModel and CropGeometry do the maths.
struct CropCanvasView: View {
    let image: UIImage
    let crop: CropRect
    /// (frame at drag start, translation in points, photo frame size) → reached a new edge
    let onMove: (CGRect, CGSize, CGSize) -> Bool
    let onResize: (CropGeometry.Handle, CGRect, CGSize, CGSize) -> Bool

    @State private var dragStart: CGRect?

    private typealias UI = Constants.CropUI
    private static let space = "cropCanvas"

    var body: some View {
        GeometryReader { geometry in
            let imageFrame = photoFrame(in: geometry.size)
            let frame = cropFrame(in: imageFrame)
            ZStack(alignment: .topLeading) {
                Image(uiImage: image)
                    .resizable()
                    .frame(width: imageFrame.width, height: imageFrame.height)
                    .position(x: imageFrame.midX, y: imageFrame.midY)
                    .accessibilityHidden(true)
                DimmedOutside(outer: imageFrame, hole: frame)
                    .fill(Color.black.opacity(UI.dimOpacity), style: FillStyle(eoFill: true))
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                Rectangle()
                    .stroke(Color.white, lineWidth: UI.frameLineWidth)
                    .frame(width: frame.width, height: frame.height)
                    .position(x: frame.midX, y: frame.midY)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                if dragStart != nil {
                    ThirdsGrid(divisions: UI.gridDivisions)
                        .stroke(Color.white.opacity(UI.gridLineOpacity), lineWidth: UI.gridLineWidth)
                        .frame(width: frame.width, height: frame.height)
                        .position(x: frame.midX, y: frame.midY)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
                moveArea(frame: frame, photoSize: imageFrame.size)
                ForEach(CropGeometry.Handle.allCases, id: \.self) { handle in
                    handleView(handle, frame: frame, photoSize: imageFrame.size)
                }
            }
            .coordinateSpace(name: Self.space)
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
        }
        .accessibilityIdentifier("edit.crop.canvas")
    }

    // MARK: Layout

    // Room is kept for the top bar above and for half a handle at the sides
    private func photoFrame(in size: CGSize) -> CGRect {
        let available = CGSize(
            width: max(size.width - 2 * UI.canvasInset, 0),
            height: max(size.height - UI.topBarClearance - UI.canvasInset, 0)
        )
        let fitted = CropGeometry.fittedFrame(imageSize: image.size, in: available)
        return fitted.offsetBy(dx: UI.canvasInset, dy: UI.topBarClearance)
    }

    private func cropFrame(in photo: CGRect) -> CGRect {
        CGRect(
            x: photo.minX + crop.x * photo.width, y: photo.minY + crop.y * photo.height,
            width: crop.width * photo.width, height: crop.height * photo.height
        )
    }

    // MARK: Gestures

    private func moveArea(frame: CGRect, photoSize: CGSize) -> some View {
        Color.clear
            .contentShape(Rectangle())
            .frame(width: frame.width, height: frame.height)
            .position(x: frame.midX, y: frame.midY)
            .gesture(drag { start, translation in onMove(start, translation, photoSize) })
            .accessibilityElement()
            .accessibilityLabel("Crop frame")
            .accessibilityHint("Drag to move the crop. Choose a preset below to set its shape.")
            .accessibilityIdentifier("edit.crop.frame")
    }

    private func handleView(_ handle: CropGeometry.Handle, frame: CGRect, photoSize: CGSize) -> some View {
        let point = CropGeometry.position(of: handle, on: frame)
        let isCorner = [.topLeft, .topRight, .bottomLeft, .bottomRight].contains(handle)
        return ZStack {
            Color.clear.contentShape(Rectangle())
            HandleMark(handle: handle, isCorner: isCorner)
                .stroke(Color.white, style: StrokeStyle(lineWidth: isCorner ? UI.cornerThickness : UI.edgeThickness, lineCap: .round, lineJoin: .round))
                .frame(width: UI.handleHitSize, height: UI.handleHitSize)
                .allowsHitTesting(false)
        }
        .frame(width: UI.handleHitSize, height: UI.handleHitSize)
        .position(x: point.x, y: point.y)
        .gesture(drag { start, translation in onResize(handle, start, translation, photoSize) })
        .accessibilityElement()
        .accessibilityLabel(handle.accessibilityLabel)
        .accessibilityHint("Drag to resize the crop")
    }

    private func drag(_ update: @escaping (CGRect, CGSize) -> Bool) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.space))
            .onChanged { value in
                let start = dragStart ?? crop.rect
                dragStart = start
                if update(start, value.translation) { Haptics.play(.detent) }
            }
            .onEnded { _ in dragStart = nil }
    }
}

// MARK: Shapes

private struct DimmedOutside: Shape {
    let outer: CGRect
    let hole: CGRect

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addRect(outer)
        path.addRect(hole)
        return path
    }
}

private struct ThirdsGrid: Shape {
    let divisions: Int

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard divisions > 1 else { return path }
        for index in 1..<divisions {
            let fraction = CGFloat(index) / CGFloat(divisions)
            path.move(to: CGPoint(x: rect.minX + rect.width * fraction, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.minX + rect.width * fraction, y: rect.maxY))
            path.move(to: CGPoint(x: rect.minX, y: rect.minY + rect.height * fraction))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + rect.height * fraction))
        }
        return path
    }
}

// The visible mark of a handle, drawn in its 44-pt hit square: an L at a
// corner, a short bar at an edge
private struct HandleMark: Shape {
    let handle: CropGeometry.Handle
    let isCorner: Bool

    func path(in rect: CGRect) -> Path {
        typealias UI = Constants.CropUI
        var path = Path()
        let centre = CGPoint(x: rect.midX, y: rect.midY)
        if isCorner {
            let arm = UI.cornerLength / 2
            let dx: CGFloat = (handle == .topLeft || handle == .bottomLeft) ? 1 : -1
            let dy: CGFloat = (handle == .topLeft || handle == .topRight) ? 1 : -1
            path.move(to: CGPoint(x: centre.x + dx * arm, y: centre.y))
            path.addLine(to: centre)
            path.addLine(to: CGPoint(x: centre.x, y: centre.y + dy * arm))
        } else {
            let half = UI.edgeLength / 2
            if handle == .top || handle == .bottom {
                path.move(to: CGPoint(x: centre.x - half, y: centre.y))
                path.addLine(to: CGPoint(x: centre.x + half, y: centre.y))
            } else {
                path.move(to: CGPoint(x: centre.x, y: centre.y - half))
                path.addLine(to: CGPoint(x: centre.x, y: centre.y + half))
            }
        }
        return path
    }
}
