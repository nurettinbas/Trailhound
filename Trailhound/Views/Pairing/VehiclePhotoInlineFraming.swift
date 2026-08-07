import SwiftUI
import UIKit

/// LinkedIn-style framing controls shown under the editor hero (no separate screen).
struct VehiclePhotoInlineFraming: View {
    @Binding var workingImage: UIImage
    @Binding var userScale: CGFloat
    @Binding var offset: CGSize
    let cropSide: CGFloat
    var onApply: () -> Void
    var onCancel: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let minZoom = VehiclePhotoCropMath.minUserScale
    private let maxZoom = VehiclePhotoCropMath.maxUserScale

    var body: some View {
        VStack(spacing: 12) {
            orientationRow
            zoomRow
            HStack(spacing: 10) {
                Button(action: onCancel) {
                    Text(L10n.cancel)
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .foregroundStyle(.primary)
                        .glassChrome(cornerRadius: GlassTokens.chipRadius)
                }
                .buttonStyle(VehiclePhotoPressStyle())

                Button(action: onApply) {
                    Text(L10n.pairingTabVehiclePhotoApply)
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .foregroundStyle(.white)
                        .background(
                            Capsule(style: .continuous)
                                .fill(TrailhoundBrandColors.brandBottom)
                        )
                }
                .buttonStyle(VehiclePhotoPressStyle())
            }
        }
        .padding(.top, 4)
        .transition(reduceMotion ? .opacity : TrailhoundMotion.softRiseTransition)
    }

    private var orientationRow: some View {
        HStack(spacing: 8) {
            orientButton("rotate.left", L10n.pairingTabVehiclePhotoRotateLeft) {
                applyOrientation(.rotateLeft)
            }
            orientButton("rotate.right", L10n.pairingTabVehiclePhotoRotateRight) {
                applyOrientation(.rotateRight)
            }
            orientButton(
                "arrow.left.and.right.righttriangle.left.righttriangle.right",
                L10n.pairingTabVehiclePhotoFlipHorizontal
            ) {
                applyOrientation(.flipHorizontal)
            }
            orientButton(
                "arrow.up.and.down.righttriangle.up.righttriangle.down",
                L10n.pairingTabVehiclePhotoFlipVertical
            ) {
                applyOrientation(.flipVertical)
            }
        }
    }

    private func orientButton(
        _ systemImage: String,
        _ label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .foregroundStyle(TrailhoundBrandColors.brandBottom)
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .glassChrome(cornerRadius: 12)
        }
        .buttonStyle(VehiclePhotoPressStyle())
        .accessibilityLabel(label)
    }

    private var zoomRow: some View {
        HStack(spacing: 12) {
            Button {
                nudgeZoom(-0.12)
            } label: {
                Image(systemName: "minus.magnifyingglass")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(TrailhoundBrandColors.brandBottom)
                    .frame(width: 34, height: 34)
                    .glassChrome(cornerRadius: 17)
            }
            .buttonStyle(VehiclePhotoPressStyle())
            .disabled(userScale <= minZoom + 0.001)

            Slider(
                value: Binding(
                    get: { userScale },
                    set: { setZoom($0, haptic: true) }
                ),
                in: minZoom ... maxZoom
            )
            .tint(TrailhoundBrandColors.brandBottom)
            .accessibilityLabel(L10n.pairingTabVehiclePhotoZoom)

            Button {
                nudgeZoom(0.12)
            } label: {
                Image(systemName: "plus.magnifyingglass")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(TrailhoundBrandColors.brandBottom)
                    .frame(width: 34, height: 34)
                    .glassChrome(cornerRadius: 17)
            }
            .buttonStyle(VehiclePhotoPressStyle())
            .disabled(userScale >= maxZoom - 0.001)
        }
    }

    private func applyOrientation(_ edit: VehiclePhotoCropMath.OrientationEdit) {
        TrailhoundHaptics.selection()
        let next = VehiclePhotoCropMath.applying(edit, to: workingImage)
        if reduceMotion {
            workingImage = next
            offset = .zero
        } else {
            withAnimation(TrailhoundMotion.photoSettle) {
                workingImage = next
                offset = .zero
            }
        }
    }

    private func nudgeZoom(_ delta: CGFloat) {
        TrailhoundHaptics.selection()
        setZoom(userScale + delta, haptic: false)
    }

    private func setZoom(_ value: CGFloat, haptic: Bool) {
        let clamped = min(max(value, minZoom), maxZoom)
        if haptic {
            let stepped = (clamped * 10).rounded() / 10
            let previous = (userScale * 10).rounded() / 10
            if stepped != previous {
                TrailhoundHaptics.selection()
            }
        }
        userScale = clamped
        let draw = VehiclePhotoCropMath.drawSize(
            imageSize: workingImage.size,
            cropSide: cropSide,
            userScale: userScale
        )
        offset = VehiclePhotoCropMath.clampedOffset(offset, drawSize: draw, cropSide: cropSide)
    }
}

/// Pan + pinch for the editor hero while framing.
struct VehiclePhotoFramingGestures: ViewModifier {
    let imageSize: CGSize
    let cropSide: CGFloat
    @Binding var userScale: CGFloat
    @Binding var offset: CGSize
    @State private var dragStart: CGSize = .zero
    @State private var pinchBase: CGFloat = VehiclePhotoCropMath.defaultUserScale

    func body(content: Content) -> some View {
        content.gesture(
            SimultaneousGesture(
                DragGesture()
                    .onChanged { value in
                        let draw = VehiclePhotoCropMath.drawSize(
                            imageSize: imageSize,
                            cropSide: cropSide,
                            userScale: userScale
                        )
                        let proposed = CGSize(
                            width: dragStart.width + value.translation.width,
                            height: dragStart.height + value.translation.height
                        )
                        offset = VehiclePhotoCropMath.clampedOffset(
                            proposed,
                            drawSize: draw,
                            cropSide: cropSide
                        )
                    }
                    .onEnded { _ in
                        dragStart = offset
                    },
                MagnificationGesture()
                    .onChanged { magnification in
                        let next = min(
                            max(pinchBase * magnification, VehiclePhotoCropMath.minUserScale),
                            VehiclePhotoCropMath.maxUserScale
                        )
                        userScale = next
                        let draw = VehiclePhotoCropMath.drawSize(
                            imageSize: imageSize,
                            cropSide: cropSide,
                            userScale: userScale
                        )
                        offset = VehiclePhotoCropMath.clampedOffset(
                            offset,
                            drawSize: draw,
                            cropSide: cropSide
                        )
                    }
                    .onEnded { _ in
                        pinchBase = userScale
                        dragStart = offset
                    }
            )
        )
        .onChange(of: userScale) { _, newValue in
            pinchBase = newValue
        }
    }
}

struct VehiclePhotoPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(TrailhoundMotion.snappy, value: configuration.isPressed)
    }
}

/// Renders the framing preview inside a square hero.
struct VehiclePhotoFramingCanvas: View {
    let image: UIImage
    let userScale: CGFloat
    let offset: CGSize
    let side: CGFloat
    var showsCheckerboard: Bool = false

    private var drawSize: CGSize {
        VehiclePhotoCropMath.drawSize(
            imageSize: image.size,
            cropSide: side,
            userScale: userScale
        )
    }

    var body: some View {
        ZStack {
            if showsCheckerboard && VehiclePhotoStore.imageHasAlpha(image) {
                CheckerboardBackground()
                    .clipShape(RoundedRectangle(cornerRadius: side * 0.18, style: .continuous))
            }
            ZStack {
                Image(uiImage: image)
                    .resizable()
                    .frame(width: drawSize.width, height: drawSize.height)
                    .offset(offset)
            }
            .frame(width: side, height: side)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: side * 0.18, style: .continuous))
        }
        .frame(width: side, height: side)
    }
}

private struct CheckerboardBackground: View {
    var body: some View {
        Canvas { context, size in
            let cell: CGFloat = 8
            var y: CGFloat = 0
            var row = 0
            while y < size.height {
                var x: CGFloat = 0
                var col = 0
                while x < size.width {
                    let dark = (row + col) % 2 == 0
                    context.fill(
                        Path(CGRect(x: x, y: y, width: cell, height: cell)),
                        with: .color(dark ? Color.secondary.opacity(0.18) : Color.secondary.opacity(0.06))
                    )
                    x += cell
                    col += 1
                }
                y += cell
                row += 1
            }
        }
    }
}
