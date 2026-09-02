//
//  ContentView.swift
//  boringNotchApp
//
//  Created by Harsh Vardhan Goswami  on 02/08/24
//  Modified by Richard Kunkli on 24/08/2024.
//

import Combine
import Defaults
import KeyboardShortcuts
import SwiftUI
import SwiftUIIntrospect

@MainActor
struct ContentView: View {
    @EnvironmentObject var vm: BoringViewModel
    @ObservedObject var coordinator = BoringViewCoordinator.shared
    @ObservedObject var musicManager = MusicManager.shared
    @ObservedObject var brightnessManager = BrightnessManager.shared
    @ObservedObject var volumeManager = VolumeManager.shared
    @State private var hoverTask: Task<Void, Never>?
    @State private var isHovering: Bool = false
    @State private var isHoverAcknowledging = false
    @State private var isExpandedContentVisible: Bool = false

    @State private var gestureProgress: CGFloat = .zero

    @State private var haptics: Bool = false

    @Namespace var albumArtNamespace

    @Default(.useMusicVisualizer) var useMusicVisualizer

    @Default(.showNotHumanFace) var showNotHumanFace

    // Hover acknowledges once by moving into the held peek state; only a click
    // may continue from that state into the full expanded panel.
    private let animationSpring = Animation.interactiveSpring(response: 0.30, dampingFraction: 0.9, blendDuration: 0)
    private let closeAnimation = Animation.spring(response: 0.32, dampingFraction: 0.98, blendDuration: 0.05)
    private let peekAnimation = Animation.spring(response: 0.27, dampingFraction: 1.0, blendDuration: 0)
    private let acknowledgeBump = Animation.spring(response: 0.10, dampingFraction: 0.55, blendDuration: 0)

    private var openAnimation: Animation {
        // Keep the existing non-music click response intact. Music gets only a
        // slightly longer response so it retains the same bouncy character.
        Animation.spring(
            response: musicManager.isPlaying ? 0.47 : 0.42,
            dampingFraction: 0.70,
            blendDuration: 0.08
        )
    }

    private let extendedHoverPadding: CGFloat = 30
    private let zeroHeightHoverPadding: CGFloat = 10

    private var notchHorizontalInset: CGFloat {
        guard vm.notchState == .open || vm.notchState == .bluetooth else { return cornerRadiusInsets.closed.bottom }
        return Defaults[.cornerRadiusScaling]
            ? cornerRadiusInsets.opened.top
            : cornerRadiusInsets.opened.bottom
    }

    private var topCornerRadius: CGFloat {
        (vm.notchState == .open || vm.notchState == .bluetooth) ? cornerRadiusInsets.opened.top : cornerRadiusInsets.closed.top
    }

    private var expandedContentWidth: CGFloat {
        max(0, vm.notchSize.width - (2 * (notchHorizontalInset + 12)))
    }

    private var currentNotchShape: NotchShape {
        NotchShape(
            topCornerRadius: topCornerRadius,
            bottomCornerRadius: (vm.notchState == .open || vm.notchState == .bluetooth)
                ? cornerRadiusInsets.opened.bottom
                : cornerRadiusInsets.closed.bottom
        )
    }

    private var computedChinWidth: CGFloat {
        var chinWidth: CGFloat = vm.closedNotchSize.width

        if coordinator.expandingView.type == .battery && coordinator.expandingView.show
            && vm.notchState == .closed && Defaults[.showPowerStatusNotifications]
        {
            chinWidth = 640
        } else if (!coordinator.expandingView.show || coordinator.expandingView.type == .music)
            && vm.notchState == .closed && (musicManager.isPlaying || !musicManager.isPlayerIdle)
            && coordinator.musicLiveActivityEnabled && !vm.hideOnClosed
        {
            chinWidth += (2 * max(0, vm.effectiveClosedNotchHeight - 12) + 20)
        } else if !coordinator.expandingView.show && vm.notchState == .closed
            && (!musicManager.isPlaying && musicManager.isPlayerIdle) && Defaults[.showNotHumanFace]
            && !vm.hideOnClosed
        {
            chinWidth += (2 * max(0, vm.effectiveClosedNotchHeight - 12) + 20)
        }

        return chinWidth
    }

    var body: some View {
        // Calculate scale based on gesture progress only
        let gestureScale: CGFloat = {
            guard gestureProgress != 0 else { return 1.0 }
            let scaleFactor = 1.0 + gestureProgress * 0.01
            return max(0.6, scaleFactor)
        }()
        
        ZStack(alignment: .top) {
            VStack(spacing: 0) {
                let mainLayout = NotchLayout()
                    // The closed music strip is wider than the physical notch because it
                    // includes album art and the visualizer. Keep that intrinsic width so
                    // the outer NotchShape never clips either end; the hover state still
                    // supplies the measured minimum peek width.
                    .frame(
                        minWidth: vm.notchState == .open
                            ? expandedContentWidth
                            : (vm.notchState == .bluetooth ? max(0, vm.notchSize.width - 24) : vm.notchSize.width),
                        maxWidth: vm.notchState == .open
                            ? expandedContentWidth
                            : (vm.notchState == .bluetooth ? max(0, vm.notchSize.width - 24) : nil),
                        minHeight: vm.notchState == .open ? max(0, vm.notchSize.height - 12) : (vm.notchState == .bluetooth ? vm.notchSize.height : nil),
                        maxHeight: vm.notchState == .open ? max(0, vm.notchSize.height - 12) : (vm.notchState == .bluetooth ? vm.notchSize.height : nil),
                        alignment: .top
                    )
                    .frame(alignment: .top)
                    .padding(
                        .horizontal,
                        notchHorizontalInset
                    )
                    .padding([.horizontal, .bottom], (vm.notchState == .open || vm.notchState == .bluetooth) ? 12 : 0)
                    .background(.black)
                    .clipShape(currentNotchShape)
                    .overlay(alignment: .top) {
                        Rectangle()
                            .fill(.black)
                            .frame(height: 1)
                            .padding(.horizontal, topCornerRadius)
                    }
                    .shadow(
                        color: ((vm.notchState == .open || isHovering) && Defaults[.enableShadow])
                            ? .black.opacity(0.7) : .clear,
                        radius: Defaults[.cornerRadiusScaling] ? 6 : 4
                    )
                    .padding(
                        .bottom,
                        vm.effectiveClosedNotchHeight == 0 ? 10 : 0
                    )
                
                mainLayout
                    // Music has a wider intrinsic closed layout than the physical
                    // notch. Apply the same 3% acknowledgement pulse to the rendered
                    // strip so it remains visible while a track is playing.
                    .scaleEffect(
                        x: musicManager.isPlaying && isHoverAcknowledging ? 1.03 : 1,
                        y: 1,
                        anchor: .top
                    )
                    .conditionalModifier(true) { view in
                        let notchAnimation: Animation
                        switch vm.notchState {
                        case .closed:
                            notchAnimation = closeAnimation
                        case .hoverPeek:
                            notchAnimation = peekAnimation
                        case .bluetooth:
                            notchAnimation = .spring(response: 0.28, dampingFraction: 0.86, blendDuration: 0)
                        case .open:
                            notchAnimation = openAnimation
                        }

                        return view
                            .animation(notchAnimation, value: vm.notchState)
                            .animation(.smooth, value: gestureProgress)
                    }
                    .contentShape(Rectangle())
                    .onChange(of: vm.isPointerInsideNotch) { _, isInside in
                        handleHover(isInside)
                    }
                    .onTapGesture {
                        if vm.notchState != .bluetooth {
                            doOpen()
                        }
                    }
                    .conditionalModifier(Defaults[.enableGestures]) { view in
                        view
                            .panGesture(direction: .down) { translation, phase in
                                handleDownGesture(translation: translation, phase: phase)
                            }
                    }
                    .conditionalModifier(Defaults[.closeGestureEnabled] && Defaults[.enableGestures]) { view in
                        view
                            .panGesture(direction: .up) { translation, phase in
                                handleUpGesture(translation: translation, phase: phase)
                            }
                    }
                    .onReceive(NotificationCenter.default.publisher(for: .sharingDidFinish)) { _ in
                        if vm.notchState == .open && !isHovering && !vm.isBatteryPopoverActive {
                            hoverTask?.cancel()
                            hoverTask = Task {
                                try? await Task.sleep(for: .milliseconds(100))
                                guard !Task.isCancelled else { return }
                                await MainActor.run {
                                    if self.vm.notchState == .open && !self.isHovering && !self.vm.isBatteryPopoverActive && !SharingStateManager.shared.preventNotchClose {
                                        self.vm.close()
                                    }
                                }
                            }
                        }
                    }
                    .onChange(of: vm.notchState) { _, newState in
                        isExpandedContentVisible = newState == .open
                        if newState == .closed && isHovering {
                            withAnimation {
                                isHovering = false
                            }
                        }
                    }
                    .onChange(of: coordinator.expandingView.show) { _, isShowing in
                        guard coordinator.expandingView.type == .bluetooth else { return }
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.86, blendDuration: 0)) {
                            if isShowing, vm.notchState != .open {
                                vm.showBluetoothConnection()
                            } else if !isShowing, vm.notchState == .bluetooth {
                                vm.close()
                            }
                        }
                    }
                    .onAppear {
                        // Cover the launch-time case where the Bluetooth device
                        // was already connected before this view subscribed to
                        // the coordinator's published notification.
                        guard coordinator.expandingView.show,
                              coordinator.expandingView.type == .bluetooth,
                              vm.notchState != .open else { return }
                        vm.showBluetoothConnection()
                    }
                    .onChange(of: vm.isBatteryPopoverActive) {
                        if !vm.isBatteryPopoverActive && !isHovering && vm.notchState == .open && !SharingStateManager.shared.preventNotchClose {
                            hoverTask?.cancel()
                            hoverTask = Task {
                                try? await Task.sleep(for: .milliseconds(100))
                                guard !Task.isCancelled else { return }
                                await MainActor.run {
                                    if !self.vm.isBatteryPopoverActive && !self.isHovering && self.vm.notchState == .open && !SharingStateManager.shared.preventNotchClose {
                                        self.vm.close()
                                    }
                                }
                            }
                        }
                    }
                    .sensoryFeedback(.alignment, trigger: haptics)
                    .contextMenu {
                        Button("Settings") {
                            DispatchQueue.main.async {
                                SettingsWindowController.shared.showWindow()
                            }
                        }
                        .keyboardShortcut(KeyEquivalent(","), modifiers: .command)
                        //                    Button("Edit") { // Doesnt work....
                        //                        let dn = DynamicNotch(content: EditPanelView())
                        //                        dn.toggle()
                        //                    }
                        //                    .keyboardShortcut("E", modifiers: .command)
                    }
                if vm.chinHeight > 0 {
                    Rectangle()
                        .fill(Color.black.opacity(0.01))
                        .frame(width: computedChinWidth, height: vm.chinHeight)
                }
            }
        }
        .padding(.bottom, 8)
        .frame(maxWidth: windowSize.width, maxHeight: windowSize.height, alignment: .top)
        .compositingGroup()
        .scaleEffect(
            x: gestureScale,
            y: gestureScale,
            anchor: .top
        )
        .animation(.smooth, value: gestureProgress)
        .preferredColorScheme(.dark)
        .environmentObject(vm)
    }

    @ViewBuilder
    func NotchLayout() -> some View {
        VStack(alignment: .leading) {
            VStack(alignment: .leading) {
                if coordinator.helloAnimationRunning {
                    Spacer()
                    HelloAnimation(onFinish: {
                        vm.closeHello()
                    }).frame(
                        width: getClosedNotchSize().width,
                        height: 80
                    )
                    .padding(.top, 40)
                    Spacer()
                } else {
                    if coordinator.expandingView.type == .bluetooth && coordinator.expandingView.show
                        && vm.notchState == .bluetooth
                    {
                        BluetoothConnectionActivity(
                            deviceName: coordinator.bluetoothDeviceName ?? "Bluetooth device",
                            isConnected: coordinator.bluetoothIsConnected
                        )
                    } else if coordinator.sneakPeek.show && Defaults[.inlineHUD] && (coordinator.sneakPeek.type != .music) && (coordinator.sneakPeek.type != .battery) && vm.notchState == .closed {
                          InlineHUD(type: $coordinator.sneakPeek.type, value: $coordinator.sneakPeek.value, icon: $coordinator.sneakPeek.icon, hoverAnimation: $isHovering, gestureProgress: $gestureProgress)
                              .transition(.opacity)
                      } else if (!coordinator.expandingView.show || coordinator.expandingView.type == .music)
                          && (vm.notchState == .closed || (vm.notchState == .hoverPeek && musicManager.isPlaying))
                          && (musicManager.isPlaying || !musicManager.isPlayerIdle)
                          && coordinator.musicLiveActivityEnabled && !vm.hideOnClosed
                      {
                          MusicLiveActivity()
                              .frame(alignment: .center)
                      } else if !coordinator.expandingView.show && vm.notchState == .closed && (!musicManager.isPlaying && musicManager.isPlayerIdle) && Defaults[.showNotHumanFace] && !vm.hideOnClosed  {
                          BoringFaceAnimation()
                       } else if vm.notchState == .open {
                           BoringHeader()
                               .frame(height: max(24, vm.effectiveClosedNotchHeight))
                               .opacity(gestureProgress != 0 ? 1.0 - min(abs(gestureProgress) * 0.1, 0.3) : 1.0)
                       } else {
                           Rectangle().fill(.clear).frame(width: vm.closedNotchSize.width - 20, height: vm.effectiveClosedNotchHeight)
                       }

                      if coordinator.sneakPeek.show {
                          if (coordinator.sneakPeek.type != .music) && (coordinator.sneakPeek.type != .battery) && !Defaults[.inlineHUD] && vm.notchState == .closed {
                              SystemEventIndicatorModifier(
                                  eventType: $coordinator.sneakPeek.type,
                                  value: $coordinator.sneakPeek.value,
                                  icon: $coordinator.sneakPeek.icon,
                                  sendEventBack: { newVal in
                                      switch coordinator.sneakPeek.type {
                                      case .volume:
                                          VolumeManager.shared.setAbsolute(Float32(newVal))
                                      case .brightness:
                                          BrightnessManager.shared.setAbsolute(value: Float32(newVal))
                                      default:
                                          break
                                      }
                                  }
                              )
                              .padding(.bottom, 10)
                              .padding(.leading, 4)
                              .padding(.trailing, 8)
                          }
                          // Old sneak peek music
                          else if coordinator.sneakPeek.type == .music {
                              if vm.notchState == .closed && !vm.hideOnClosed && Defaults[.sneakPeekStyles] == .standard {
                                  HStack(alignment: .center) {
                                      Image(systemName: "music.note")
                                      GeometryReader { geo in
                                          MarqueeText(.constant(musicManager.songTitle + " - " + musicManager.artistName),  textColor: Defaults[.playerColorTinting] ? Color(nsColor: musicManager.avgColor).ensureMinimumBrightness(factor: 0.6) : .gray, minDuration: 1, frameWidth: geo.size.width)
                                      }
                                  }
                                  .foregroundStyle(.gray)
                                  .padding(.bottom, 10)
                              }
                          }
                      }
                  }
              }
              .conditionalModifier((coordinator.sneakPeek.show && (coordinator.sneakPeek.type == .music) && vm.notchState == .closed && !vm.hideOnClosed && Defaults[.sneakPeekStyles] == .standard) || (coordinator.sneakPeek.show && (coordinator.sneakPeek.type != .music) && (vm.notchState == .closed))) { view in
                  view
                      .fixedSize()
              }
              .zIndex(2)
            if vm.notchState == .open {
                NotchHomeView(albumArtNamespace: albumArtNamespace)
                .zIndex(1)
                .allowsHitTesting(vm.notchState == .open)
                .opacity(isExpandedContentVisible ? (gestureProgress != 0 ? 1.0 - min(abs(gestureProgress) * 0.1, 0.3) : 1.0) : 0)
                .blur(radius: isExpandedContentVisible ? 0 : 10)
                .animation(
                    .spring(response: 0.22, dampingFraction: 0.9)
                        .delay(isExpandedContentVisible ? 0.08 : 0),
                    value: isExpandedContentVisible
                )
            }
        }
    }

    @ViewBuilder
    func BoringFaceAnimation() -> some View {
        HStack {
            HStack {
                Rectangle()
                    .fill(.clear)
                    .frame(
                        width: max(0, vm.effectiveClosedNotchHeight - 12),
                        height: max(0, vm.effectiveClosedNotchHeight - 12)
                    )
                Rectangle()
                    .fill(.black)
                    .frame(width: vm.closedNotchSize.width - 20)
                MinimalFaceFeatures()
            }
        }.frame(
            height: vm.effectiveClosedNotchHeight,
            alignment: .center
        )
    }

    @ViewBuilder
    func MusicLiveActivity() -> some View {
        HStack {
            Image(nsImage: musicManager.albumArt)
                .resizable()
                .clipped()
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: MusicPlayerImageSizes.cornerRadiusInset.closed)
                )
                .matchedGeometryEffect(id: "albumArt", in: albumArtNamespace)
                .frame(
                    width: max(0, vm.effectiveClosedNotchHeight - 12),
                    height: max(0, vm.effectiveClosedNotchHeight - 12)
                )

            Rectangle()
                .fill(.black)
                .overlay(
                    HStack(alignment: .top) {
                        if coordinator.expandingView.show
                            && coordinator.expandingView.type == .music
                        {
                            MarqueeText(
                                .constant(musicManager.songTitle),
                                textColor: Defaults[.coloredSpectrogram]
                                    ? Color(nsColor: musicManager.avgColor) : Color.gray,
                                minDuration: 0.4,
                                frameWidth: 100
                            )
                            .opacity(
                                (coordinator.expandingView.show
                                    && Defaults[.sneakPeekStyles] == .inline)
                                    ? 1 : 0
                            )
                            Spacer(minLength: vm.closedNotchSize.width)
                            // Song Artist
                            Text(musicManager.artistName)
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .foregroundStyle(
                                    Defaults[.coloredSpectrogram]
                                        ? Color(nsColor: musicManager.avgColor)
                                        : Color.gray
                                )
                                .opacity(
                                    (coordinator.expandingView.show
                                        && coordinator.expandingView.type == .music
                                        && Defaults[.sneakPeekStyles] == .inline)
                                        ? 1 : 0
                                )
                        }
                    }
                )
                .frame(
                    width: (coordinator.expandingView.show
                        && coordinator.expandingView.type == .music
                        && Defaults[.sneakPeekStyles] == .inline)
                        ? 380
                        : vm.closedNotchSize.width
                            + -cornerRadiusInsets.closed.top
                )

            HStack {
                if useMusicVisualizer {
                    Rectangle()
                        .fill(
                            Defaults[.coloredSpectrogram]
                                ? Color(nsColor: musicManager.avgColor).gradient
                                : Color.gray.gradient
                        )
                        .frame(width: 50, alignment: .center)
                        .matchedGeometryEffect(id: "spectrum", in: albumArtNamespace)
                        .mask {
                            AudioSpectrumView(isPlaying: $musicManager.isPlaying)
                                .frame(width: 16, height: 12)
                        }
                } else {
                    LottieAnimationContainer()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(
                width: max(
                    0,
                    vm.effectiveClosedNotchHeight - 12
                        + gestureProgress / 2
                ),
                height: max(
                    0,
                    vm.effectiveClosedNotchHeight - 12
                ),
                alignment: .center
            )
        }
        .frame(
            height: vm.effectiveClosedNotchHeight,
            alignment: .center
        )
    }

    private func doOpen() {
        hoverTask?.cancel()
        withAnimation(acknowledgeBump) {
            isHoverAcknowledging = false
        }
        withAnimation(openAnimation) {
            vm.open()
        }
    }

    // MARK: - Hover Management

    private func handleHover(_ hovering: Bool) {
        if coordinator.firstLaunch { return }
        hoverTask?.cancel()

        // Bluetooth connection cards are transient notifications, not panels.
        // Pointer movement must neither promote them to the music panel nor
        // dismiss them before their short display interval ends.
        if vm.notchState == .bluetooth { return }
        
        if hovering {
            withAnimation(animationSpring) {
                isHovering = true
            }
            
            if vm.notchState == .closed && Defaults[.enableHaptics] {
                haptics.toggle()
            }
            
            guard vm.notchState == .closed,
                  !coordinator.sneakPeek.show,
                  Defaults[.openNotchOnHover] else { return }
            
            // A single outward, lightly bouncy motion settles at the held peek
            // size. This intentionally replaces the former bump-retract-peek
            // sequence, which felt like two acknowledgements.
            withAnimation(acknowledgeBump) {
                isHoverAcknowledging = false
                vm.showHoverPeek()
            }
        } else {
            // Once the full panel is open, a genuine pointer exit should begin
            // closing straight away. The delayed bounds check below is only for
            // the compact hover-peek transition, where resizing can emit a
            // transient exit event.
            if vm.notchState == .open {
                withAnimation(closeAnimation) {
                    isHoverAcknowledging = false
                    isHovering = false
                    if !vm.isBatteryPopoverActive && !SharingStateManager.shared.preventNotchClose {
                        vm.close()
                    }
                }
                return
            }

            if vm.notchState == .hoverPeek {
                // The panel-level monitor emits this only after the pointer
                // truly leaves the current live bounds, even during rapid
                // enter/exit testing.
                withAnimation(closeAnimation) {
                    isHoverAcknowledging = false
                    isHovering = false
                    vm.close()
                }
                return
            }

            withAnimation(acknowledgeBump) {
                isHoverAcknowledging = false
                if vm.notchState == .closed {
                    vm.resetHoverAcknowledgement()
                }
            }
            hoverTask = Task {
                try? await Task.sleep(for: .milliseconds(100))
                guard !Task.isCancelled else { return }
                
                await MainActor.run {
                    // SwiftUI can briefly report a hover exit while the notch changes
                    // size. Only close after the pointer has genuinely left the live
                    // notch bounds, so the sustained hover peek remains held.
                    guard !self.vm.isMouseHovering() else { return }

                    withAnimation(animationSpring) {
                        self.isHovering = false
                    }
                    
                    if self.vm.notchState != .closed && !self.vm.isBatteryPopoverActive && !SharingStateManager.shared.preventNotchClose {
                        self.vm.close()
                    }
                }
            }
        }
    }

    // MARK: - Gesture Handling

    private func handleDownGesture(translation: CGFloat, phase: NSEvent.Phase) {
        guard vm.notchState == .closed else { return }

        if phase == .ended {
            withAnimation(animationSpring) { gestureProgress = .zero }
            return
        }

        withAnimation(animationSpring) {
            gestureProgress = (translation / Defaults[.gestureSensitivity]) * 20
        }

        if translation > Defaults[.gestureSensitivity] {
            if Defaults[.enableHaptics] {
                haptics.toggle()
            }
            withAnimation(animationSpring) {
                gestureProgress = .zero
            }
            doOpen()
        }
    }

    private func handleUpGesture(translation: CGFloat, phase: NSEvent.Phase) {
        guard vm.notchState == .open && !vm.isHoveringCalendar else { return }

        withAnimation(animationSpring) {
            gestureProgress = (translation / Defaults[.gestureSensitivity]) * -20
        }

        if phase == .ended {
            withAnimation(animationSpring) {
                gestureProgress = .zero
            }
        }

        if translation > Defaults[.gestureSensitivity] {
            withAnimation(animationSpring) {
                isHovering = false
            }
            if !SharingStateManager.shared.preventNotchClose { 
                gestureProgress = .zero
                vm.close()
            }

            if Defaults[.enableHaptics] {
                haptics.toggle()
            }
        }
    }
}

struct FullScreenDropDelegate: DropDelegate {
    @Binding var isTargeted: Bool
    let onDrop: () -> Void

    func dropEntered(info _: DropInfo) {
        isTargeted = true
    }

    func dropExited(info _: DropInfo) {
        isTargeted = false
    }

    func performDrop(info _: DropInfo) -> Bool {
        isTargeted = false
        onDrop()
        return true
    }

}

struct GeneralDropTargetDelegate: DropDelegate {
    @Binding var isTargeted: Bool

    func dropEntered(info: DropInfo) {
        isTargeted = true
    }

    func dropExited(info: DropInfo) {
        isTargeted = false
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        return DropProposal(operation: .cancel)
    }

    func performDrop(info: DropInfo) -> Bool {
        return false
    }
}

private struct BluetoothConnectionActivity: View {
    let deviceName: String
    let isConnected: Bool

    @State private var hasAppeared = false
    @State private var yawRight = false

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Label(isConnected ? "Connected" : "Disconnected", systemImage: "bluetooth")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(isConnected ? .green : .red)

                Text(deviceName)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.72)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Image("OnePlusBuds")
                .resizable()
                .scaledToFit()
                .frame(width: 84, height: 60)
                .scaleEffect(hasAppeared ? 0.82 : 0.574)
                .rotation3DEffect(
                    .degrees(yawRight ? 16 : -16),
                    axis: (x: 0, y: 1, z: 0),
                    perspective: 0.7
                )
                .rotationEffect(.degrees(yawRight ? 1.5 : -1.5))
                .animation(.spring(response: 0.34, dampingFraction: 0.78), value: hasAppeared)
                .animation(.easeInOut(duration: 1.35).repeatForever(autoreverses: true), value: yawRight)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        // Keep both card elements clear of the physical notch without changing
        // the Bluetooth card's outer size.
        .offset(y: 24)
        .onAppear {
            hasAppeared = true
            yawRight = true
        }
    }
}

#Preview {
    let vm = BoringViewModel()
    vm.open()
    return ContentView()
        .environmentObject(vm)
        .frame(width: vm.notchSize.width, height: vm.notchSize.height)
}
