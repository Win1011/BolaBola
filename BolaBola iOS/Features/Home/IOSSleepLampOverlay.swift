import SwiftUI
import UIKit

/// 睡眠时间主界面关灯动效：下拉灯绳触发；灯罩为完整 `SleepLampBg`。
struct IOSSleepLampOverlay: View {
    let onSleep: () -> Void

    /// 垂在灯罩图下缘的偏移（更小 = 绳整体上移）。
    private let cordHangBelowLamp: CGFloat = 90

    private let lampImageAspectHeightFactor: CGFloat = 235.0 / 402.0
    /// 灯罩整块向上微调（pt），动画插值小数像素时顶住「顶层露缝」，一般 2〜4 即可；绳子挂点同步扣减同等高度。
    private let lampTopRenderBleed: CGFloat = 3

    // MARK: - 待机摆绳（略放慢）

    private let cordSwingDegrees: Double = 3.5
    private let cordSwingDuration: CGFloat = 3.4
    private let cordSwingInitialDelay: CGFloat = 2.0

    // MARK: - 下拉后段落（整体比初版慢一点）

    private let lampDropSpringResponse: CGFloat = 1.12
    private let lampDropSpringDamping: CGFloat = 0.85

    /// 云层 spring：`response` 越大整体越舒展（更慢）；与灯罩下拉节奏错开一点点。
    private let cloudRevealDelay: CGFloat = 1.05
    private let cloudRevealSpringResponse: CGFloat = 1.65
    private let cloudRevealSpringDamping: CGFloat = 0.80

    private let darkenDelay: CGFloat = 1.62
    /// 不要用 `easeIn`：会先慢后快，后半的黑场像「一下子糊满」显得在变快。
    private let darkenDuration: CGFloat = 2.55

    private let messageDelay: CGFloat = 3.05
    private let messageFadeInDuration: CGFloat = 0.58

    private let dismissDelay: CGFloat = 5.85
    private let dismissFadeDuration: CGFloat = 1.05

    @State private var unitOffsetY: CGFloat = -400
    @State private var cloudOffsetX: CGFloat = -220
    @State private var lightsOpacity: Double = 0
    @State private var textOpacity: Double = 0
    @State private var cordSwing: Double = 0
    @State private var triggered = false
    @State private var dragOffset: CGFloat = 0
    @State private var didStartCordSwing = false

    var body: some View {
        GeometryReader { geo in
            let layoutW = geo.size.width
            let lampImageHeight = layoutW * lampImageAspectHeightFactor
            let cordCenterX: CGFloat = layoutW - 30
            // 相对 GeometryReader 顶边 (y=0)；不用 safeAreaInsets（导航栈会变）。
            let cordCenterY: CGFloat = unitOffsetY + lampImageHeight + cordHangBelowLamp - lampTopRenderBleed
                + dragOffset * 0.32

            ZStack(alignment: .topLeading) {
                Color.black
                    .opacity(lightsOpacity * 0.9)
                    .ignoresSafeArea()
                    .allowsHitTesting(lightsOpacity > 0.05)

                ZStack(alignment: .topLeading) {
                    ZStack(alignment: .topLeading) {
                        Image("SleepLampBg")
                            .resizable()
                            .interpolation(.high)
                            .scaledToFit()
                            .frame(width: layoutW)
                        Image("SleepCloudMoon")
                            .resizable()
                            .interpolation(.high)
                            .scaledToFit()
                            .frame(width: 110)
                            .offset(x: layoutW * 0.10 + cloudOffsetX, y: lampImageHeight * 0.28)
                    }
                    // 整块光栅化后平移：减轻 spring + 半透明边在顶缘与下层背景合成的细线闪烁。
                    .drawingGroup(opaque: false)
                    .offset(y: -lampTopRenderBleed)
                    .frame(width: layoutW, alignment: .leading)
                    .offset(y: unitOffsetY)
                    .allowsHitTesting(false)

                    Image("SleepCord")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 40, height: 227)
                        .rotationEffect(.degrees(cordSwing + dragOffset * 0.10), anchor: .top)
                        .position(x: cordCenterX, y: cordCenterY)
                        .gesture(
                            SimultaneousGesture(
                                TapGesture().onEnded {
                                    handleTrigger()
                                },
                                DragGesture(minimumDistance: 8)
                                    .onChanged { value in
                                        guard !triggered else { return }
                                        let dy = max(0, value.translation.height)
                                        dragOffset = min(dy, 80)
                                        if dragOffset >= 55 {
                                            handleTrigger()
                                        }
                                    }
                                    .onEnded { _ in
                                        guard !triggered else { return }
                                        withAnimation(.spring(response: 0.48, dampingFraction: 0.64)) {
                                            dragOffset = 0
                                        }
                                    }
                            )
                        )
                }

                VStack(spacing: 16) {
                    Spacer()
                    Image(systemName: "moon.stars.fill")
                        .font(.system(size: 48, weight: .light))
                        .foregroundStyle(.white.opacity(0.88))
                    Text("晚安喽")
                        .font(.system(size: 38, weight: .ultraLight))
                        .foregroundStyle(.white)
                    Spacer()
                }
                .opacity(textOpacity)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .allowsHitTesting(false)
            }
            .onAppear {
                applyIdleHiddenOffset(lampHeight: lampImageHeight, layoutTooSmall: layoutW <= 4)
                startCordSwingIfNeeded()
            }
            .onChange(of: geo.size.width) { _, width in
                let h = width * lampImageAspectHeightFactor
                applyIdleHiddenOffset(lampHeight: h, layoutTooSmall: width <= 4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
    }

    /// 父级 Proposal 在变（进出设置栈、幕后布局等）但 `unitOffsetY` 若仍按旧宽高算，会与当前 `cordCenterY`/`lampImageHeight` 脱节，绳子就会忽高忽低。
    private func applyIdleHiddenOffset(lampHeight: CGFloat, layoutTooSmall: Bool) {
        if layoutTooSmall { return }
        guard !triggered else { return }
        guard lampHeight >= 48 else { return }
        unitOffsetY = -lampHeight
    }

    private func startCordSwingIfNeeded() {
        guard !didStartCordSwing else { return }
        didStartCordSwing = true
        withAnimation(
            .easeInOut(duration: Double(cordSwingDuration))
                .repeatForever(autoreverses: true)
                .delay(Double(cordSwingInitialDelay))
        ) {
            cordSwing = cordSwingDegrees
        }
    }

    private func handleTrigger() {
        guard !triggered else { return }
        triggered = true
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        withAnimation(.spring(response: Double(lampDropSpringResponse), dampingFraction: Double(lampDropSpringDamping))) {
            unitOffsetY = 0
            dragOffset = 0
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + cloudRevealDelay) {
            withAnimation(.spring(response: Double(cloudRevealSpringResponse), dampingFraction: Double(cloudRevealSpringDamping))) {
                cloudOffsetX = 0
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + darkenDelay) {
            withAnimation(.easeInOut(duration: darkenDuration)) {
                lightsOpacity = 1.0
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + messageDelay) {
            withAnimation(.easeIn(duration: messageFadeInDuration)) {
                textOpacity = 1.0
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + dismissDelay) {
            onSleep()
            withAnimation(.easeOut(duration: dismissFadeDuration)) {
                lightsOpacity = 0
                textOpacity = 0
            }
        }
    }
}
