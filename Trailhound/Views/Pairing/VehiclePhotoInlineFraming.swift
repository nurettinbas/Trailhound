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
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .brightness(configuration.isPressed ? -0.04 : 0)
            .animation(TrailhoundMotion.snappy, value: configuration.isPressed)
    }
}

/// Empty-state add photo control — corner badge (v-badge style), intro bounces twice together.
struct EmptyVehiclePhotoAddButton: View {
    let title: String
    var isDisabled: Bool = false
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var bounceOffset: CGFloat = 0
    @State private var showBadge = true
    @State private var badgeOpacity: Double = 1
    @State private var didPlayIntro = false

    private let bounceAmplitude: CGFloat = 8
    private let bounceDuration: TimeInterval = 0.64
    private let bounceStep: Duration = .milliseconds(640)
    private let badgeFadeDuration: TimeInterval = 0.7

    /// Base orb was ~56pt; +30% diameter.
    private let orbDiameter: CGFloat = 56 * 1.3
    /// Chip position: +20% further right from prior x=22.
    private let badgeOffsetX: CGFloat = 22 * 1.2
    private let badgeOffsetY: CGFloat = -12
    private let badgeTopClearance: CGFloat = 20

    private var containerHeight: CGFloat {
        orbDiameter + badgeTopClearance + bounceAmplitude + 6
    }

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .top) {
                ZStack(alignment: .topTrailing) {
                    cameraOrb

                    if showBadge {
                        photoBadge
                            .opacity(badgeOpacity)
                            .offset(x: badgeOffsetX, y: badgeOffsetY)
                    }
                }
                .offset(y: badgeTopClearance + bounceAmplitude + bounceOffset)
            }
            .frame(width: orbDiameter + 36, height: containerHeight, alignment: .top)
        }
        .buttonStyle(VehiclePhotoPressStyle())
        .disabled(isDisabled)
        .accessibilityLabel(title)
        .onAppear(perform: playIntroIfNeeded)
    }

    private var photoBadge: some View {
        Text(title)
            .font(.system(size: 9, weight: .bold))
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                Capsule(style: .continuous)
                    .fill(TrailhoundBrandColors.brandBottom)
            )
            .overlay {
                Capsule(style: .continuous)
                    .strokeBorder(Color.white, lineWidth: 1.5)
            }
            .shadow(color: .black.opacity(0.22), radius: 2, y: 1)
            .allowsHitTesting(false)
    }

    private func playIntroIfNeeded() {
        guard !didPlayIntro else { return }
        didPlayIntro = true

        if reduceMotion {
            showBadge = false
            return
        }

        Task { @MainActor in
            for _ in 0 ..< 2 {
                withAnimation(.easeInOut(duration: bounceDuration)) {
                    bounceOffset = -bounceAmplitude
                }
                try? await Task.sleep(for: bounceStep)
                withAnimation(.easeInOut(duration: bounceDuration)) {
                    bounceOffset = 0
                }
                try? await Task.sleep(for: bounceStep)
            }

            withAnimation(.easeOut(duration: badgeFadeDuration)) {
                badgeOpacity = 0
            }
            try? await Task.sleep(for: .milliseconds(Int(badgeFadeDuration * 1000)))
            showBadge = false
        }
    }

    private var cameraOrb: some View {
        Image(systemName: "camera.fill")
            .font(.system(size: 22, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: orbDiameter, height: orbDiameter)
            .background(
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                TrailhoundBrandColors.brandBottom,
                                TrailhoundBrandColors.brandBottom.opacity(0.78)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay {
                Circle()
                    .strokeBorder(.white.opacity(0.38), lineWidth: 1.5)
            }
            .shadow(color: TrailhoundBrandColors.brandBottom.opacity(0.32), radius: 10, y: 4)
            .shadow(color: .black.opacity(0.16), radius: 5, y: 2)
    }
}

/// Renders the framing preview inside a square hero.
struct VehiclePhotoFramingCanvas: View {
    let image: UIImage
    let userScale: CGFloat
    let offset: CGSize
    let side: CGFloat
    var showsCheckerboard: Bool = false
    var showsCropChrome: Bool = true
    var showsExtendedPreview: Bool = true

    private var cornerRadius: CGFloat { side * 0.18 }

    private var drawSize: CGSize {
        VehiclePhotoCropMath.drawSize(
            imageSize: image.size,
            cropSide: side,
            userScale: userScale
        )
    }

    /// Extra space around the crop window so zoomed-in overflow stays visible (dimmed).
    private var overflowPadding: CGFloat {
        guard showsExtendedPreview else { return 0 }
        let extraW = max(0, (drawSize.width - side) / 2)
        let extraH = max(0, (drawSize.height - side) / 2)
        return min(max(extraW, extraH), 52)
    }

    private var containerSide: CGFloat { side + overflowPadding * 2 }

    private var showsLetterbox: Bool {
        drawSize.width < side - 0.5 || drawSize.height < side - 0.5
    }

    var body: some View {
        ZStack {
            if overflowPadding > 0 {
                imageLayer
                    .opacity(0.34)
                    .allowsHitTesting(false)
            }

            cropWindowContent

            if showsCropChrome {
                VehiclePhotoCropFrameOverlay(cornerRadius: cornerRadius)
                    .frame(width: side, height: side)
            }
        }
        .frame(width: containerSide, height: containerSide)
        .animation(TrailhoundMotion.snappy, value: userScale)
        .animation(TrailhoundMotion.snappy, value: offset)
    }

    private var cropWindowContent: some View {
        ZStack {
            letterboxBackground

            imageLayer
        }
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    @ViewBuilder
    private var letterboxBackground: some View {
        if showsCheckerboard && VehiclePhotoStore.imageHasAlpha(image) {
            CheckerboardBackground()
        } else if showsLetterbox {
            Color.primary.opacity(0.08)
        }
    }

    private var imageLayer: some View {
        Image(uiImage: image)
            .resizable()
            .frame(width: drawSize.width, height: drawSize.height)
            .offset(offset)
    }
}

/// Visible crop boundary while framing — shows exactly what will be saved.
private struct VehiclePhotoCropFrameOverlay: View {
    let cornerRadius: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(Color.black.opacity(0.38), lineWidth: 3)

            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(Color.white.opacity(0.95), lineWidth: 2)

            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(TrailhoundBrandColors.brandBottom.opacity(0.55), lineWidth: 1)
                .padding(2)
        }
        .shadow(color: .black.opacity(0.28), radius: 8, y: 3)
        .allowsHitTesting(false)
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
