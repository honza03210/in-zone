import SwiftUI

struct RoomSetupView: View {
    @EnvironmentObject var roomStore: RoomStore
    @Environment(\.dismiss) var dismiss

    @State private var width: String = ""
    @State private var height: String = ""
    @State private var anchors: [AnchorPlacement] = []
    @State private var draggedAnchor: UInt8?
    @FocusState private var dimensionFieldFocused: Bool

    private var currentWidth: Float { max(1, Self.parseDimension(width) ?? 5) }
    private var currentHeight: Float { max(1, Self.parseDimension(height) ?? 4) }

    // Decimal pads produce "," as the separator in many locales
    static func parseDimension(_ text: String) -> Float? {
        Float(text.replacingOccurrences(of: ",", with: "."))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                dimensionFields

                Text("Drag anchors to match your room layout")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                setupCanvas
                    .padding(.horizontal)

                anchorList
                    .padding(.horizontal)

                Spacer(minLength: 0)
            }
            .navigationTitle("Room Setup")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { dimensionFieldFocused = false }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button("Reset to Defaults") { resetDefaults() }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 8)
            }
            .onAppear {
                width = String(format: "%.1f", roomStore.layout.width)
                height = String(format: "%.1f", roomStore.layout.height)
                anchors = roomStore.layout.anchors
            }
            .onChange(of: width) { _ in clampAnchors() }
            .onChange(of: height) { _ in clampAnchors() }
        }
    }

    // MARK: - Dimensions

    private var dimensionFields: some View {
        HStack(spacing: 20) {
            HStack(spacing: 6) {
                Text("W")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                TextField("5.0", text: $width)
                    .keyboardType(.decimalPad)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 56)
                    .focused($dimensionFieldFocused)
                Text("m")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            HStack(spacing: 6) {
                Text("H")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                TextField("4.0", text: $height)
                    .keyboardType(.decimalPad)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 56)
                    .focused($dimensionFieldFocused)
                Text("m")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.top, 8)
    }

    // MARK: - Canvas

    private var setupCanvas: some View {
        GeometryReader { geo in
            let roomW = CGFloat(currentWidth)
            let roomH = CGFloat(currentHeight)
            let margin: CGFloat = 32
            let usable = CGSize(width: geo.size.width - margin * 2,
                                height: geo.size.height - margin * 2)
            let scale = min(usable.width / roomW, usable.height / roomH)
            let ox = (geo.size.width - roomW * scale) / 2
            let oy = (geo.size.height - roomH * scale) / 2

            ZStack {
                gridAndBorder(roomW: roomW, roomH: roomH, scale: scale,
                              ox: ox, oy: oy, viewSize: geo.size)

                meterLabels(roomW: roomW, roomH: roomH, scale: scale,
                            ox: ox, oy: oy)

                ForEach(anchors) { anchor in
                    draggableAnchor(anchor, scale: scale, ox: ox, oy: oy)
                }
            }
        }
        .aspectRatio(CGFloat(currentWidth) / CGFloat(currentHeight), contentMode: .fit)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private func gridAndBorder(roomW: CGFloat, roomH: CGFloat, scale: CGFloat,
                               ox: CGFloat, oy: CGFloat, viewSize: CGSize) -> some View {
        ForEach(0...max(1, Int(roomW)), id: \.self) { x in
            Path { p in
                let vx = ox + CGFloat(x) * scale
                p.move(to: CGPoint(x: vx, y: oy))
                p.addLine(to: CGPoint(x: vx, y: oy + roomH * scale))
            }
            .stroke(.primary.opacity(0.06), lineWidth: 0.5)
        }
        ForEach(0...max(1, Int(roomH)), id: \.self) { y in
            Path { p in
                let vy = oy + CGFloat(y) * scale
                p.move(to: CGPoint(x: ox, y: vy))
                p.addLine(to: CGPoint(x: ox + roomW * scale, y: vy))
            }
            .stroke(.primary.opacity(0.06), lineWidth: 0.5)
        }
        Rectangle()
            .stroke(.primary.opacity(0.4), lineWidth: 1.5)
            .frame(width: roomW * scale, height: roomH * scale)
            .position(x: viewSize.width / 2, y: viewSize.height / 2)
    }

    @ViewBuilder
    private func meterLabels(roomW: CGFloat, roomH: CGFloat, scale: CGFloat,
                             ox: CGFloat, oy: CGFloat) -> some View {
        ForEach(0...max(1, Int(roomW)), id: \.self) { x in
            Text("\(x)m")
                .font(.system(size: 8))
                .foregroundStyle(.tertiary)
                .position(x: ox + CGFloat(x) * scale, y: oy + roomH * scale + 14)
        }
        ForEach(0...max(1, Int(roomH)), id: \.self) { y in
            Text("\(y)")
                .font(.system(size: 8))
                .foregroundStyle(.tertiary)
                .position(x: ox - 14, y: oy + CGFloat(y) * scale)
        }
    }

    @ViewBuilder
    private func draggableAnchor(_ anchor: AnchorPlacement, scale: CGFloat,
                                  ox: CGFloat, oy: CGFloat) -> some View {
        let pt = CGPoint(x: ox + CGFloat(anchor.x) * scale,
                         y: oy + CGFloat(anchor.y) * scale)
        let isDragging = draggedAnchor == anchor.id

        Text(anchor.label.isEmpty ? "A\(anchor.id)" : anchor.label)
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(.red.opacity(0.8))
            .position(x: pt.x, y: pt.y - 18)

        Circle()
            .fill(.red)
            .frame(width: 22, height: 22)
            .overlay(
                Text("\(anchor.id)")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
            )
            .shadow(color: isDragging ? .red.opacity(0.5) : .clear, radius: 8)
            .scaleEffect(isDragging ? 1.2 : 1.0)
            .position(pt)
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .local)
                    .onChanged { value in
                        draggedAnchor = anchor.id
                        let x = Float((value.location.x - ox) / scale)
                        let y = Float((value.location.y - oy) / scale)
                        if let idx = anchors.firstIndex(where: { $0.id == anchor.id }) {
                            anchors[idx].x = max(0, min(currentWidth, x))
                            anchors[idx].y = max(0, min(currentHeight, y))
                        }
                    }
                    .onEnded { _ in
                        withAnimation(.easeOut(duration: 0.2)) { draggedAnchor = nil }
                    }
            )
            .animation(.interactiveSpring(), value: isDragging)

        Text(String(format: "(%.1f, %.1f)", anchor.x, anchor.y))
            .font(.system(size: 7, design: .monospaced))
            .foregroundStyle(.tertiary)
            .position(x: pt.x, y: pt.y + 18)
    }

    // MARK: - Anchor list

    private var anchorList: some View {
        VStack(spacing: 6) {
            ForEach(anchors) { anchor in
                HStack(spacing: 8) {
                    Circle()
                        .fill(.red)
                        .frame(width: 8, height: 8)
                    Text("A\(anchor.id)")
                        .font(.caption.bold().monospacedDigit())
                    Text(anchor.label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(String(format: "(%.1f, %.1f) m", anchor.x, anchor.y))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Actions

    private func save() {
        // Dimensions may have shrunk after anchors were placed
        let clamped = anchors.map { a in
            var a = a
            a.x = max(0, min(currentWidth, a.x))
            a.y = max(0, min(currentHeight, a.y))
            return a
        }
        roomStore.layout = RoomLayout(
            width: currentWidth,
            height: currentHeight,
            anchors: clamped
        )
        roomStore.save()
        dismiss()
    }

    private func clampAnchors() {
        for idx in anchors.indices {
            anchors[idx].x = max(0, min(currentWidth, anchors[idx].x))
            anchors[idx].y = max(0, min(currentHeight, anchors[idx].y))
        }
    }

    private func resetDefaults() {
        width = "5.0"
        height = "4.0"
        anchors = RoomLayout.defaultAnchors
    }
}
