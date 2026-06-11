import SwiftUI

struct RoomCanvasView: View {
    @EnvironmentObject var roomStore: RoomStore
    @EnvironmentObject var zoneStore: ZoneStore
    @EnvironmentObject var zoneEngine: ZoneEngine
    @EnvironmentObject var scheduler: RangingScheduler
    @EnvironmentObject var simulator: SimulatorService

    var compact = false

    private var layout: RoomLayout { roomStore.layout }

    private var phonePosition: CGPoint? {
        if simulator.isActive && simulator.isRanging {
            return simulator.phonePosition
        }
        if scheduler.isRunning && !scheduler.currentDistances.isEmpty {
            return Trilateration.estimatePosition(
                distances: scheduler.currentDistances,
                anchors: layout.anchors
            )
        }
        return nil
    }

    private var isRanging: Bool {
        (simulator.isActive && simulator.isRanging) || scheduler.isRunning
    }

    var body: some View {
        GeometryReader { geo in
            canvas(in: geo.size)
        }
        .aspectRatio(CGFloat(layout.width) / CGFloat(layout.height), contentMode: .fit)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: compact ? 12 : 16))
    }

    // MARK: - Canvas

    @ViewBuilder
    private func canvas(in size: CGSize) -> some View {
        let roomW = CGFloat(layout.width)
        let roomH = CGFloat(layout.height)
        let margin: CGFloat = compact ? 18 : 32
        let usable = CGSize(width: size.width - margin * 2,
                            height: size.height - margin * 2)
        let scale = min(usable.width / roomW, usable.height / roomH)
        let ox = (size.width - roomW * scale) / 2
        let oy = (size.height - roomH * scale) / 2

        let ctx = CanvasContext(roomW: roomW, roomH: roomH,
                                scale: scale, ox: ox, oy: oy)
        let phone = phonePosition.map { ctx.clamp($0) }

        ZStack {
            gridLines(ctx)
            roomBorder(ctx, size: size)
            zoneBlobs(ctx)
            if isRanging { distanceLines(ctx, phone: phone) }
            phoneDot(ctx, phone: phone)
            anchorDots(ctx)
            if !compact { meterLabels(ctx) }
        }
        .contentShape(Rectangle())
        .gesture(simulatorDragGesture(ctx))
    }

    // MARK: - Coordinate helpers

    private struct CanvasContext {
        let roomW: CGFloat, roomH: CGFloat
        let scale: CGFloat, ox: CGFloat, oy: CGFloat

        func viewPt(_ room: CGPoint) -> CGPoint {
            CGPoint(x: ox + room.x * scale, y: oy + room.y * scale)
        }

        func viewPt(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: ox + x * scale, y: oy + y * scale)
        }

        func roomPt(from view: CGPoint) -> CGPoint {
            CGPoint(x: (view.x - ox) / scale, y: (view.y - oy) / scale)
        }

        func clamp(_ p: CGPoint) -> CGPoint {
            CGPoint(x: max(0, min(roomW, p.x)), y: max(0, min(roomH, p.y)))
        }
    }

    // MARK: - Grid

    @ViewBuilder
    private func gridLines(_ c: CanvasContext) -> some View {
        let cols = max(1, Int(c.roomW))
        let rows = max(1, Int(c.roomH))
        ForEach(0...cols, id: \.self) { x in
            Path { p in
                let vx = c.ox + CGFloat(x) * c.scale
                p.move(to: CGPoint(x: vx, y: c.oy))
                p.addLine(to: CGPoint(x: vx, y: c.oy + c.roomH * c.scale))
            }
            .stroke(.primary.opacity(0.07), lineWidth: 0.5)
        }
        ForEach(0...rows, id: \.self) { y in
            Path { p in
                let vy = c.oy + CGFloat(y) * c.scale
                p.move(to: CGPoint(x: c.ox, y: vy))
                p.addLine(to: CGPoint(x: c.ox + c.roomW * c.scale, y: vy))
            }
            .stroke(.primary.opacity(0.07), lineWidth: 0.5)
        }
    }

    // MARK: - Room border

    private func roomBorder(_ c: CanvasContext, size: CGSize) -> some View {
        Rectangle()
            .stroke(.primary.opacity(0.4), lineWidth: 1.5)
            .frame(width: c.roomW * c.scale, height: c.roomH * c.scale)
            .position(x: size.width / 2, y: size.height / 2)
    }

    // MARK: - Zone blobs

    @ViewBuilder
    private func zoneBlobs(_ c: CanvasContext) -> some View {
        ForEach(zoneStore.zones) { zone in
            zoneBlob(zone, c)
        }
    }

    @ViewBuilder
    private func zoneBlob(_ zone: Zone, _ c: CanvasContext) -> some View {
        if let center = Trilateration.estimateFromFingerprint(zone.fingerprint,
                                                              anchors: layout.anchors) {
            let clamped = c.clamp(center)
            let pt = c.viewPt(clamped)
            let radius = blobRadius(zone) * c.scale
            let isActive = zone.id == zoneEngine.currentZone?.id
            let color = Zone.color(for: zone.colorName)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            color.opacity(isActive ? 0.40 : 0.22),
                            color.opacity(isActive ? 0.08 : 0.03)
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: radius
                    )
                )
                .frame(width: radius * 2, height: radius * 2)
                .overlay(
                    Circle()
                        .stroke(color.opacity(isActive ? 0.7 : 0.35),
                                lineWidth: isActive ? 2 : 1)
                )
                .position(pt)

            Circle()
                .fill(color.opacity(isActive ? 0.9 : 0.6))
                .frame(width: compact ? 4 : 6, height: compact ? 4 : 6)
                .position(pt)

            Text(zone.name)
                .font(.system(size: compact ? 9 : 12, weight: .semibold))
                .foregroundStyle(color.opacity(isActive ? 1 : 0.7))
                .position(x: pt.x, y: pt.y - radius - (compact ? 7 : 10))
        } else {
            // Trilateration needs >= 2 anchors; show a range ring instead
            singleAnchorRing(zone, c)
        }
    }

    @ViewBuilder
    private func singleAnchorRing(_ zone: Zone, _ c: CanvasContext) -> some View {
        if let entry = zone.fingerprint.first,
           zone.fingerprint.count == 1,
           let anchorId = UInt8(entry.key),
           let placement = layout.anchor(for: anchorId) {
            let anchorRoom = CGPoint(x: CGFloat(placement.x), y: CGFloat(placement.y))
            let radius = CGFloat(entry.value.mean) * c.scale
            let isActive = zone.id == zoneEngine.currentZone?.id
            let color = Zone.color(for: zone.colorName)

            Circle()
                .stroke(color.opacity(isActive ? 0.7 : 0.35),
                        style: StrokeStyle(lineWidth: isActive ? 2 : 1, dash: [4, 3]))
                .frame(width: radius * 2, height: radius * 2)
                .position(c.viewPt(anchorRoom))

            // Label sits on the ring, on the side facing the room center
            let dx = c.roomW / 2 - anchorRoom.x
            let dy = c.roomH / 2 - anchorRoom.y
            let len = max(sqrt(dx * dx + dy * dy), 0.001)
            let labelRoom = CGPoint(
                x: anchorRoom.x + dx / len * CGFloat(entry.value.mean),
                y: anchorRoom.y + dy / len * CGFloat(entry.value.mean)
            )
            Text(zone.name)
                .font(.system(size: compact ? 9 : 12, weight: .semibold))
                .foregroundStyle(color.opacity(isActive ? 1 : 0.7))
                .position(c.viewPt(c.clamp(labelRoom)))
        }
    }

    /// The blob shows capture uncertainty (~2 sigma of the fingerprint
    /// noise), not the detection range — matching happens in
    /// anchor-distance space, so the zone has no true spatial extent.
    private func blobRadius(_ zone: Zone) -> CGFloat {
        guard !zone.fingerprint.isEmpty else { return 0.4 }
        let avgStd = zone.fingerprint.values
            .map { sqrt($0.variance) }
            .reduce(0, +) / Float(zone.fingerprint.count)
        return CGFloat(max(0.3, min(1.2, 2 * avgStd)))
    }

    // MARK: - Distance lines

    @ViewBuilder
    private func distanceLines(_ c: CanvasContext, phone: CGPoint?) -> some View {
        if let phone {
            let pp = c.viewPt(phone)
            ForEach(layout.anchors) { anchor in
                let ap = c.viewPt(CGFloat(anchor.x), CGFloat(anchor.y))
                Path { path in
                    path.move(to: pp)
                    path.addLine(to: ap)
                }
                .stroke(.blue.opacity(0.12), lineWidth: 1)
            }
        }
    }

    // MARK: - Phone

    @ViewBuilder
    private func phoneDot(_ c: CanvasContext, phone: CGPoint?) -> some View {
        if let phone {
            let pt = c.viewPt(phone)
            let dotSize: CGFloat = compact ? 16 : 20
            Circle()
                .fill(.blue)
                .frame(width: dotSize, height: dotSize)
                .shadow(color: .blue.opacity(0.5), radius: 6)
                .overlay(
                    Image(systemName: "iphone")
                        .font(.system(size: compact ? 8 : 10))
                        .foregroundStyle(.white)
                )
                .position(pt)
        }
    }

    // MARK: - Anchors

    @ViewBuilder
    private func anchorDots(_ c: CanvasContext) -> some View {
        ForEach(layout.anchors) { anchor in
            let pt = c.viewPt(CGFloat(anchor.x), CGFloat(anchor.y))
            let dotSize: CGFloat = compact ? 8 : 11

            Circle()
                .fill(.red.opacity(0.85))
                .frame(width: dotSize, height: dotSize)
                .position(pt)

            if compact {
                Text("A\(anchor.id)")
                    .font(.system(size: 7, weight: .bold, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .position(x: pt.x, y: pt.y - 8)
            } else {
                Text(anchor.label.isEmpty ? "A\(anchor.id)" : anchor.label)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .position(x: pt.x, y: pt.y - 12)
            }

            if !compact, let dist = scheduler.currentDistances[anchor.id] {
                Text(String(format: "%.1fm", dist))
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .position(x: pt.x, y: pt.y + 12)
            }
        }
    }

    // MARK: - Meter labels

    @ViewBuilder
    private func meterLabels(_ c: CanvasContext) -> some View {
        let cols = max(1, Int(c.roomW))
        let rows = max(1, Int(c.roomH))
        ForEach(0...cols, id: \.self) { x in
            Text("\(x)m")
                .font(.system(size: 8))
                .foregroundStyle(.tertiary)
                .position(x: c.ox + CGFloat(x) * c.scale,
                          y: c.oy + c.roomH * c.scale + 14)
        }
        ForEach(0...rows, id: \.self) { y in
            Text("\(y)")
                .font(.system(size: 8))
                .foregroundStyle(.tertiary)
                .position(x: c.ox - 14,
                          y: c.oy + CGFloat(y) * c.scale)
        }
    }

    // MARK: - Simulator drag

    private func simulatorDragGesture(_ c: CanvasContext) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                guard simulator.isActive && simulator.isRanging else { return }
                let room = c.roomPt(from: value.location)
                simulator.phonePosition = c.clamp(room)
            }
    }
}
