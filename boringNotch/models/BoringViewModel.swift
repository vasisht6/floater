//
//  BoringViewModel.swift
//  boringNotch
//
//  Created by Harsh Vardhan  Goswami  on 04/08/24.
//

import Combine
import Defaults
import SwiftUI

class BoringViewModel: NSObject, ObservableObject {
    @ObservedObject var coordinator = BoringViewCoordinator.shared
    @ObservedObject var detector = FullscreenMediaDetector.shared

    let animationLibrary: BoringAnimations = .init()
    let animation: Animation?

    @Published var contentType: ContentType = .normal
    @Published private(set) var notchState: NotchState = .closed

    var cancellables: Set<AnyCancellable> = []
    
    @Published var hideOnClosed: Bool = true

    @Published var edgeAutoOpenActive: Bool = false
    @Published var isHoveringCalendar: Bool = false
    @Published var isBatteryPopoverActive: Bool = false
    @Published var isPointerInsideNotch: Bool = false

    @Published var screenUUID: String?

    @Published var notchSize: CGSize = getClosedNotchSize()
    @Published var closedNotchSize: CGSize = getClosedNotchSize()
    
    
    deinit {
        destroy()
    }

    func destroy() {
        cancellables.forEach { $0.cancel() }
        cancellables.removeAll()
    }

    init(screenUUID: String? = nil) {
        animation = animationLibrary.animation

        super.init()
        
        self.screenUUID = screenUUID
        notchSize = getClosedNotchSize(screenUUID: screenUUID)
        closedNotchSize = notchSize

        setupDetectorObserver()
    }
    
    private func setupDetectorObserver() {
        // Publisher for the user’s fullscreen detection setting
        let enabledPublisher = Defaults
            .publisher(.hideNotchOption)
            .map(\.newValue)
            .map { $0 != .never }
            .removeDuplicates()

        // Publisher for the current screen UUID (non-nil, distinct)
        let screenPublisher = $screenUUID
            .compactMap { $0 }
            .removeDuplicates()

        // Publisher for fullscreen status dictionary
        let fullscreenStatusPublisher = detector.$fullscreenStatus
            .removeDuplicates()

        // Combine all three: screen UUID, fullscreen status, and enabled setting
        Publishers.CombineLatest3(screenPublisher, fullscreenStatusPublisher, enabledPublisher)
            .map { screenUUID, fullscreenStatus, enabled in
                let isFullscreen = fullscreenStatus[screenUUID] ?? false
                return enabled && isFullscreen
            }
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] shouldHide in
                withAnimation(.smooth) {
                    self?.hideOnClosed = shouldHide
                }
            }
            .store(in: &cancellables)
    }

    // Computed property for effective notch height
    var effectiveClosedNotchHeight: CGFloat {
        let currentScreen = screenUUID.flatMap { NSScreen.screen(withUUID: $0) }
        let noNotchAndFullscreen = hideOnClosed && (currentScreen?.safeAreaInsets.top ?? 0 <= 0 || currentScreen == nil)
        guard !noNotchAndFullscreen else { return 0 }
        return (notchState == .hoverPeek || notchState == .bluetooth)
            ? notchSize.height : closedNotchSize.height
    }

    /// Matches the rendered footprint used for pointer handling. The closed
    /// music activity extends beyond the physical hardware-notch width.
    var interactiveNotchSize: CGSize {
        if notchState == .bluetooth {
            return notchSize
        }

        guard notchState != .open else { return notchSize }

        let isShowingMusicActivity = (!coordinator.expandingView.show || coordinator.expandingView.type == .music)
            && (MusicManager.shared.isPlaying || !MusicManager.shared.isPlayerIdle)
            && coordinator.musicLiveActivityEnabled
            && !hideOnClosed

        guard isShowingMusicActivity else { return notchSize }

        let musicSideWidth = max(0, effectiveClosedNotchHeight - 12)
        let renderedMusicWidth = closedNotchSize.width + (2 * musicSideWidth) + 8

        return CGSize(
            width: max(notchSize.width, renderedMusicWidth),
            height: notchSize.height
        )
    }

    var chinHeight: CGFloat {
        if !Defaults[.hideTitleBar] {
            return 0
        }

        guard let currentScreen = screenUUID.flatMap({ NSScreen.screen(withUUID: $0) }) else {
            return 0
        }

        if notchState == .open { return 0 }

        let menuBarHeight = currentScreen.frame.maxY - currentScreen.visibleFrame.maxY
        let currentHeight = effectiveClosedNotchHeight

        if currentHeight == 0 { return 0 }

        return max(0, menuBarHeight - currentHeight)
    }

    func isMouseHovering(position: NSPoint = NSEvent.mouseLocation) -> Bool {
        let screenFrame = getScreenFrame(screenUUID)
        if let frame = screenFrame {
            
            let baseY = frame.maxY - notchSize.height
            let baseX = frame.midX - notchSize.width / 2
            
            return position.y >= baseY && position.x >= baseX && position.x <= baseX + notchSize.width
        }
        
        return false
    }

    func open() {
        self.notchSize = openNotchSize
        self.notchState = .open
        
        // Force music information update when notch is opened
        MusicManager.shared.forceUpdate()
    }

    func beginHoverAcknowledgement() {
        let closedSize = getClosedNotchSize(screenUUID: screenUUID)
        closedNotchSize = closedSize
        notchSize = CGSize(width: closedSize.width * 1.03, height: closedSize.height)
    }

    func resetHoverAcknowledgement() {
        let closedSize = getClosedNotchSize(screenUUID: screenUUID)
        closedNotchSize = closedSize
        notchSize = closedSize
    }

    func showHoverPeek() {
        let closedSize = getClosedNotchSize(screenUUID: screenUUID)
        closedNotchSize = closedSize
        notchSize = CGSize(width: closedSize.width * 1.13, height: closedSize.height * 1.13)
        notchState = .hoverPeek
    }

    func showBluetoothConnection() {
        let closedSize = getClosedNotchSize(screenUUID: screenUUID)
        closedNotchSize = closedSize
        notchSize = CGSize(width: 276, height: 92)
        notchState = .bluetooth
    }

    func close() {
        // Do not close while a share picker or sharing service is active
        if SharingStateManager.shared.preventNotchClose {
            return
        }
        self.notchSize = getClosedNotchSize(screenUUID: self.screenUUID)
        self.closedNotchSize = self.notchSize
        self.notchState = .closed
        self.isBatteryPopoverActive = false
        self.coordinator.sneakPeek.show = false
        self.edgeAutoOpenActive = false

    }

    func closeHello() {
        Task { @MainActor in
            withAnimation(animationLibrary.animation) {
                coordinator.helloAnimationRunning = false
                close()
            }
        }
    }
}
