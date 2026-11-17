import AppKit
import ApplicationServices

/// Captures the currently selected text from the frontmost app.
/// Strategy: Accessibility API first; fall back to synthesizing ⌘C and reading the pasteboard.
enum SelectionCapture {
    struct Result: Sendable {
        let text: String
        let source: LearningVocabularySource?
    }

    @MainActor
    static func capture(from sourceApp: NSRunningApplication) async -> Result? {
        let targetPID = sourceApp.processIdentifier
        let appID = sourceApp.bundleIdentifier
        let appName = sourceApp.localizedName
        guard targetPID != getpid() else {
            DebugLog.log("selection-capture: skipped no external source")
            return nil
        }
        DebugLog.log("selection-capture: sourcePID=\(targetPID) foregroundPID=\(NSWorkspace.shared.frontmostApplication?.processIdentifier ?? 0)")
        // Accessibility calls are synchronous IPC. An unresponsive source app must
        // not freeze Parrot's main thread while the shortcut is being handled.
        let ax = await Task.detached(priority: .userInitiated) {
            selectionViaAccessibility(from: targetPID, appID: appID, appName: appName)
        }.value
        guard !Task.isCancelled else {
            DebugLog.log("selection-capture: cancelled after accessibility read")
            return nil
        }
        DebugLog.log("  AX path -> \(ax.text.map { "len=\($0.count)" } ?? "nil")")
        if let text = ax.text {
            return Result(text: text, source: ax.source)
        }
        let copy = await selectedTextViaCopy(from: targetPID)
        DebugLog.log("  Copy path -> \(copy.map { "len=\($0.count)" } ?? "nil")")
        return copy.map { Result(text: $0, source: ax.source) }
    }

    /// Read the focused UI element's selected text through the Accessibility API.
    /// Skips elements owned by our own process (e.g. the floating result panel), whose
    /// selection would otherwise shadow the real frontmost app on repeat invocations.
    private static func selectionViaAccessibility(
        from targetPID: pid_t,
        appID: String?,
        appName: String?
    ) -> (text: String?, source: LearningVocabularySource?) {
        let app = AXUIElementCreateApplication(targetPID)
        let appFocus = focusedElement(in: app, expectedPID: targetPID, route: "application")
        if let appFocus, let text = selectedText(in: appFocus) {
            return (text, captureSource(focused: appFocus, app: app, appID: appID, appName: appName))
        }

        // Some apps expose the focused element through the system-wide AX object
        // but not their application object. Never accept another app's selection.
        let systemFocus = focusedElement(
            in: AXUIElementCreateSystemWide(),
            expectedPID: targetPID,
            route: "system"
        )
        let text = systemFocus.flatMap(selectedText(in:))
        let source = captureSource(focused: systemFocus ?? appFocus, app: app, appID: appID, appName: appName)
        return (text, source)
    }

    private static func focusedElement(in root: AXUIElement, expectedPID: pid_t, route: String) -> AXUIElement? {
        AXUIElementSetMessagingTimeout(root, 0.15)
        var focused: AnyObject?
        let focusStatus = AXUIElementCopyAttributeValue(root, kAXFocusedUIElementAttribute as CFString, &focused)
        guard focusStatus == .success, let element = focused, CFGetTypeID(element) == AXUIElementGetTypeID() else {
            DebugLog.log("selection-capture: AX \(route) focus unavailable status=\(focusStatus.rawValue)")
            return nil
        }

        let axElement = element as! AXUIElement
        AXUIElementSetMessagingTimeout(axElement, 0.15)

        // Reject Parrot and stale focus in any other process, including the fallback.
        var pid: pid_t = 0
        guard AXUIElementGetPid(axElement, &pid) == .success, pid == expectedPID, pid != getpid() else {
            DebugLog.log("selection-capture: AX \(route) ignored focusPID=\(pid) expectedPID=\(expectedPID)")
            return nil
        }
        return axElement
    }

    private static func selectedText(in axElement: AXUIElement) -> String? {
        var value: AnyObject?
        let selectionStatus = AXUIElementCopyAttributeValue(axElement, kAXSelectedTextAttribute as CFString, &value)
        guard selectionStatus == .success, let text = value as? String, !text.isEmpty else {
            DebugLog.log("selection-capture: AX no selected text status=\(selectionStatus.rawValue)")
            return nil
        }
        return text
    }

    private static func captureSource(
        focused: AXUIElement?,
        app: AXUIElement,
        appID: String?,
        appName: String?
    ) -> LearningVocabularySource? {
        // Source is optional. Bound the AX reads so slow apps cannot hold up text capture.
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .milliseconds(90))
        func attribute(_ name: CFString, of element: AXUIElement) -> AnyObject? {
            guard clock.now < deadline, !Task.isCancelled else { return nil }
            AXUIElementSetMessagingTimeout(element, 0.035)
            var value: AnyObject?
            guard AXUIElementCopyAttributeValue(element, name, &value) == .success else { return nil }
            return value
        }
        func element(_ name: CFString, of parent: AXUIElement) -> AXUIElement? {
            guard let value = attribute(name, of: parent), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
            return (value as! AXUIElement)
        }
        func url(_ value: AnyObject?) -> URL? {
            (value as? URL) ?? (value as? String).flatMap { URL(string: $0) }
        }

        let window = focused.flatMap { element(kAXWindowAttribute as CFString, of: $0) }
            ?? element(kAXFocusedWindowAttribute as CFString, of: app)
        var webArea: AXUIElement?
        var ancestor: AXUIElement? = focused
        for _ in 0..<16 {
            guard let node = ancestor else { break }
            let role = attribute(kAXRoleAttribute as CFString, of: node) as? String
            if role == "AXWebArea" { webArea = node }
            if role == kAXWindowRole as String { break }
            ancestor = element(kAXParentAttribute as CFString, of: node)
        }

        // Reading the web area's URL avoids confusing an inline hyperlink with the page itself.
        let pageURL = webArea.flatMap { url(attribute(kAXURLAttribute as CFString, of: $0)) }
        let document = window.flatMap { attribute(kAXDocumentAttribute as CFString, of: $0) }
        let location = pageURL ?? url(document) ?? window.flatMap { url(attribute(kAXURLAttribute as CFString, of: $0)) }
        if let location, location.isFileURL {
            return LearningVocabularySource(title: location.lastPathComponent)
        }
        if let path = document as? String, path.hasPrefix("/") {
            return LearningVocabularySource(title: URL(fileURLWithPath: path).lastPathComponent)
        }
        if let documentName = document as? String, url(document)?.scheme == nil, pageURL == nil {
            return LearningVocabularySource(title: documentName, url: location)
        }

        let webTitle = webArea.flatMap { attribute(kAXTitleAttribute as CFString, of: $0) as? String }
        if let source = LearningVocabularySource(title: webTitle, url: location), source.title != nil {
            return source
        }

        // Some native editors expose the document name only in the window title.
        // Limit the fallback to document apps instead of saving arbitrary app chrome.
        let canUseWindowTitle = webArea != nil || location != nil || appID.map(documentWindowAppIDs.contains) == true
        let windowTitle = canUseWindowTitle
            ? window.flatMap { attribute(kAXTitleAttribute as CFString, of: $0) as? String }
            : nil
        return LearningVocabularySource(title: windowTitle == appName ? nil : windowTitle, url: location)
    }

    private static let documentWindowAppIDs: Set<String> = [
        "com.apple.iWork.Pages", "com.apple.Preview", "com.apple.TextEdit", "com.microsoft.Word"
    ]

    /// Fallback: preserve the pasteboard, send ⌘C, read the copy, then restore.
    @MainActor
    private static func selectedTextViaCopy(from targetPID: pid_t?) async -> String? {
        guard !Task.isCancelled else {
            DebugLog.log("selection-capture: copy skipped cancelled")
            return nil
        }
        guard let targetPID, targetPID != getpid() else {
            DebugLog.log("selection-capture: copy skipped no external source")
            return nil
        }
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == targetPID else {
            DebugLog.log("selection-capture: copy skipped foreground changed")
            return nil
        }
        let liveFlags = NSEvent.modifierFlags
        DebugLog.log("  copy: preFlags=0x\(String(liveFlags.rawValue, radix: 16)) option=\(liveFlags.contains(.option)) command=\(liveFlags.contains(.command)) control=\(liveFlags.contains(.control)) shift=\(liveFlags.contains(.shift))")

        // On macOS 26/27 a held hotkey modifier can leak into the synthetic copy,
        // even with a private event source. Yield while waiting for its release.
        guard await waitForHotkeyModifiersToClear(from: targetPID),
              !Task.isCancelled,
              NSWorkspace.shared.frontmostApplication?.processIdentifier == targetPID else {
            DebugLog.log("selection-capture: copy skipped after modifier wait")
            return nil
        }

        let pasteboard = NSPasteboard.general
        let savedChangeCount = pasteboard.changeCount
        let savedItems: [NSPasteboardItem] = pasteboard.pasteboardItems?.map { item in
            let snapshot = NSPasteboardItem()
            for type in item.types {
                if let data = item.data(forType: type) {
                    snapshot.setData(data, forType: type)
                }
            }
            return snapshot
        } ?? []
        guard pasteboard.changeCount == savedChangeCount else {
            DebugLog.log("selection-capture: copy skipped clipboard changed during snapshot")
            return nil
        }

        sendCommandC()

        // Yield between checks instead of running a nested main RunLoop. This keeps
        // input and rendering responsive and avoids reentrant shortcut handling.
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .milliseconds(600))
        while clock.now < deadline {
            guard !Task.isCancelled,
                  NSWorkspace.shared.frontmostApplication?.processIdentifier == targetPID else {
                DebugLog.log("selection-capture: copy abandoned cancelled or foreground changed")
                return nil
            }
            if pasteboard.changeCount != savedChangeCount {
                let copiedChangeCount = pasteboard.changeCount
                let current = pasteboard.string(forType: .string)
                // A user may switch apps or copy something else while capture waits.
                // Restore only the copy we observed, never a newer clipboard change.
                guard !Task.isCancelled,
                      NSWorkspace.shared.frontmostApplication?.processIdentifier == targetPID else { return nil }
                if pasteboard.changeCount == copiedChangeCount {
                    pasteboard.clearContents()
                    if !savedItems.isEmpty { pasteboard.writeObjects(savedItems) }
                }
                return current?.isEmpty == false ? current : nil
            }
            do { try await Task.sleep(for: .milliseconds(20)) }
            catch {
                DebugLog.log("selection-capture: copy wait cancelled")
                return nil
            }
        }
        // If no copy happened, the clipboard was never touched.
        DebugLog.log("selection-capture: copy timed out without clipboard change")
        return nil
    }

    /// Synthesize ⌘C using a private event source and explicit command flags.
    /// The modifier-release wait above also protects macOS versions that merge
    /// physically held hotkey modifiers into events from a private source.
    private static func sendCommandC() {
        let source = CGEventSource(stateID: .privateState)
        source?.setLocalEventsFilterDuringSuppressionState([], state: .eventSuppressionStateSuppressionInterval)

        let cKey: CGKeyCode = 8 // 'c'
        let down = CGEvent(keyboardEventSource: source, virtualKey: cKey, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: cKey, keyDown: false)
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        DebugLog.log("  copy: post ⌘C down.flags=0x\(String(down?.flags.rawValue ?? 0, radix: 16)) up.flags=0x\(String(up?.flags.rawValue ?? 0, radix: 16))")
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }

    /// Whether the app has Accessibility permission (needed for AX read & key synthesis).
    static func hasAccessibilityPermission(prompt: Bool) -> Bool {
        AppPermissions.accessibility(prompt: prompt)
    }

    @MainActor
    private static func waitForHotkeyModifiersToClear(from targetPID: pid_t) async -> Bool {
        let watched: NSEvent.ModifierFlags = [.option, .control, .command, .shift]
        let clock = ContinuousClock()
        let start = clock.now
        let deadline = start.advanced(by: .milliseconds(250))
        while clock.now < deadline {
            guard !Task.isCancelled,
                  NSWorkspace.shared.frontmostApplication?.processIdentifier == targetPID else {
                return false
            }
            if NSEvent.modifierFlags.intersection(watched).isEmpty {
                let waited = start.duration(to: clock.now)
                DebugLog.log("  copy: modifiers cleared after \(waited)")
                return true
            }
            do { try await Task.sleep(for: .milliseconds(10)) }
            catch { return false }
        }
        DebugLog.log("  copy: modifier release timed out after 250ms flags=0x\(String(NSEvent.modifierFlags.rawValue, radix: 16))")
        return true
    }
}
