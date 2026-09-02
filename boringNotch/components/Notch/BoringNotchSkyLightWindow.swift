//
//  BoringNotchSkyLightWindow.swift
//  boringNotch
//
//  Created by Alexander on 2025-10-20.
//

import Cocoa
import SwiftUI
import SkyLightWindow
import Defaults
import Combine

extension SkyLightOperator {
    func undelegateWindow(_ window: NSWindow) {
        typealias F_SLSRemoveWindowsFromSpaces = @convention(c) (Int32, CFArray, CFArray) -> Int32
        
        let handler = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/Versions/A/SkyLight", RTLD_NOW)
        guard let SLSRemoveWindowsFromSpaces = unsafeBitCast(
            dlsym(handler, "SLSRemoveWindowsFromSpaces"),
            to: F_SLSRemoveWindowsFromSpaces?.self
        ) else {
            return
        }
        
        // Remove the window from the SkyLight space
        _ = SLSRemoveWindowsFromSpaces(
            connection,
            [window.windowNumber] as CFArray,
            [space] as CFArray
        )
    }
}

class BoringNotchSkyLightWindow: NSPanel {
    private var isSkyLightEnabled: Bool = false
    private var globalMouseMonitor: Any?
    private var localMouseMonitor: Any?
    private var pointerIsInsideNotch = false

    /// Supplies the visible notch footprint inside this otherwise transparent panel.
    /// The panel ignores events everywhere else so it cannot cover browser controls.
    var interactiveNotchSizeProvider: (() -> CGSize)? {
        didSet { updateMousePassthrough() }
    }

    /// Reports changes from the panel-level pointer monitor. This remains
    /// reliable while the window toggles mouse pass-through around its edges.
    var pointerInsideNotchDidChange: ((Bool) -> Void)?
    
    override init(
        contentRect: NSRect,
        styleMask: NSWindow.StyleMask,
        backing: NSWindow.BackingStoreType,
        defer flag: Bool
    ) {
        super.init(
            contentRect: contentRect,
            styleMask: styleMask,
            backing: backing,
            defer: flag
        )
        
        configureWindow()
        setupObservers()
        installMousePassthroughMonitors()
    }
    
    private func configureWindow() {
        isFloatingPanel = true
        isOpaque = false
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        backgroundColor = .clear
        isMovable = false
        ignoresMouseEvents = false
        acceptsMouseMovedEvents = true
        level = .mainMenu + 3
        hasShadow = false
        isReleasedWhenClosed = false
        
        // Force dark appearance regardless of system setting
        appearance = NSAppearance(named: .darkAqua)
        
        collectionBehavior = [
            .fullScreenAuxiliary,
            .stationary,
            .canJoinAllSpaces,
            .ignoresCycle,
        ]
        
        // Apply initial sharing type setting
        updateSharingType()
    }
    
    private func setupObservers() {
        // Listen for changes to the hideFromScreenRecording setting
        Defaults.publisher(.hideFromScreenRecording)
            .sink { [weak self] _ in
                self?.updateSharingType()
            }
            .store(in: &observers)
    }

    private func installMousePassthroughMonitors() {
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved]) { [weak self] _ in
            DispatchQueue.main.async {
                self?.updateMousePassthrough()
            }
        }

        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved]) { [weak self] event in
            self?.updateMousePassthrough()
            return event
        }

        updateMousePassthrough()
    }

    private func updateMousePassthrough() {
        guard let notchSize = interactiveNotchSizeProvider?() else { return }

        let notchFrame = CGRect(
            x: frame.midX - notchSize.width / 2,
            y: frame.maxY - notchSize.height,
            width: notchSize.width,
            height: notchSize.height
        )
        // `CGRect.contains` excludes the rectangle's maximum edges. The top edge
        // of this panel is also the top edge of the display, so use inclusive
        // bounds to keep clicks at the highest reachable cursor position inside
        // the notch hit region.
        let mouseLocation = NSEvent.mouseLocation
        let shouldReceiveMouseEvents = mouseLocation.x >= notchFrame.minX
            && mouseLocation.x <= notchFrame.maxX
            && mouseLocation.y >= notchFrame.minY
            && mouseLocation.y <= notchFrame.maxY

        if pointerIsInsideNotch != shouldReceiveMouseEvents {
            pointerIsInsideNotch = shouldReceiveMouseEvents
            pointerInsideNotchDidChange?(shouldReceiveMouseEvents)
        }

        if ignoresMouseEvents == shouldReceiveMouseEvents {
            ignoresMouseEvents = !shouldReceiveMouseEvents
        }

        // The global monitor also runs when a SwiftUI child view owns the
        // current pointer event. Reinstate the regular pointer here so text
        // and slider subviews cannot leave the cursor hidden or as an I-beam.
        if shouldReceiveMouseEvents {
            DispatchQueue.main.async {
                NSCursor.setHiddenUntilMouseMoves(false)
                NSCursor.unhide()
                NSCursor.arrow.set()
            }
        }
    }
    
    private func updateSharingType() {
        if Defaults[.hideFromScreenRecording] {
            sharingType = .none
        } else {
            sharingType = .readWrite
        }
    }
    
    func enableSkyLight() {
        if !isSkyLightEnabled {
            SkyLightOperator.shared.delegateWindow(self)
            isSkyLightEnabled = true
        }
    }
    
    func disableSkyLight() {
        if isSkyLightEnabled {
            SkyLightOperator.shared.undelegateWindow(self)
            isSkyLightEnabled = false
        }
    }
    
    private var observers: Set<AnyCancellable> = []

    deinit {
        if let globalMouseMonitor { NSEvent.removeMonitor(globalMouseMonitor) }
        if let localMouseMonitor { NSEvent.removeMonitor(localMouseMonitor) }
    }
    
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Keeps the system arrow cursor visible while it is over the non-activating
/// notch panel. SwiftUI's hosting view otherwise has no explicit cursor rect.
final class NotchHostingView: NSHostingView<AnyView> {
    private var cursorTrackingArea: NSTrackingArea?

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .arrow)
    }

    override func cursorUpdate(with event: NSEvent) {
        super.cursorUpdate(with: event)
        scheduleArrowCursor()
    }

    override func updateTrackingAreas() {
        if let cursorTrackingArea {
            removeTrackingArea(cursorTrackingArea)
        }

        let trackingArea = NSTrackingArea(
            rect: .zero,
            options: [.activeAlways, .inVisibleRect, .mouseEnteredAndExited, .mouseMoved, .cursorUpdate],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        cursorTrackingArea = trackingArea
        super.updateTrackingAreas()
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        scheduleArrowCursor()
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        scheduleArrowCursor()
    }

    private func scheduleArrowCursor() {
        // SwiftUI can set an I-beam while it dispatches the same mouse event to
        // a child text view. Applying the arrow on the next main-loop pass
        // keeps the panel's cursor consistent without affecting click handling.
        DispatchQueue.main.async {
            self.showArrowCursor()
        }
    }

    private func showArrowCursor() {
        // Ensure a previously hidden AppKit cursor is restored before applying
        // the standard pointer inside the notch panel.
        NSCursor.setHiddenUntilMouseMoves(false)
        NSCursor.unhide()
        NSCursor.arrow.set()
    }
}
