import SwiftUI

struct SimulatorRoomView: View {
    @EnvironmentObject var simulator: SimulatorService

    var body: some View {
        VStack(spacing: 4) {
            HStack {
                Image(systemName: "play.desktopcomputer")
                    .foregroundStyle(.orange)
                Text("Simulator")
                    .font(.caption.bold())
                    .foregroundStyle(.orange)
                Spacer()
                Text("Drag to move")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            GeometryReader { geo in
                let roomW = simulator.roomSize.width
                let roomH = simulator.roomSize.height
                let scale = min(geo.size.width / roomW, geo.size.height / roomH)
                let ox = (geo.size.width - roomW * scale) / 2
                let oy = (geo.size.height - roomH * scale) / 2

                ZStack {
                    Rectangle()
                        .stroke(.secondary.opacity(0.5), lineWidth: 1.5)
                        .frame(width: roomW * scale, height: roomH * scale)
                        .position(x: geo.size.width / 2, y: geo.size.height / 2)

                    ForEach(SimulatorService.anchorPositions) { ap in
                        let pt = viewPoint(ap.x, ap.y, ox: ox, oy: oy, scale: scale)
                        let phonePt = viewPoint(
                            simulator.phonePosition.x,
                            simulator.phonePosition.y,
                            ox: ox, oy: oy, scale: scale
                        )

                        Path { path in
                            path.move(to: phonePt)
                            path.addLine(to: pt)
                        }
                        .stroke(.secondary.opacity(0.2), lineWidth: 1)

                        Circle()
                            .fill(.red.opacity(0.8))
                            .frame(width: 10, height: 10)
                            .position(pt)

                        Text("A\(ap.id)")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .position(x: pt.x, y: pt.y - 10)
                    }

                    let phonePt = viewPoint(
                        simulator.phonePosition.x,
                        simulator.phonePosition.y,
                        ox: ox, oy: oy, scale: scale
                    )
                    Circle()
                        .fill(.blue)
                        .frame(width: 22, height: 22)
                        .shadow(color: .blue.opacity(0.4), radius: 4)
                        .overlay(
                            Image(systemName: "iphone")
                                .font(.system(size: 11))
                                .foregroundStyle(.white)
                        )
                        .position(phonePt)
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0, coordinateSpace: .local)
                        .onChanged { value in
                            let x = (value.location.x - ox) / scale
                            let y = (value.location.y - oy) / scale
                            simulator.phonePosition = CGPoint(
                                x: max(0, min(roomW, x)),
                                y: max(0, min(roomH, y))
                            )
                        }
                )
            }
            .aspectRatio(
                simulator.roomSize.width / simulator.roomSize.height,
                contentMode: .fit
            )
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private func viewPoint(_ rx: CGFloat, _ ry: CGFloat,
                            ox: CGFloat, oy: CGFloat, scale: CGFloat) -> CGPoint {
        CGPoint(x: ox + rx * scale, y: oy + ry * scale)
    }
}
