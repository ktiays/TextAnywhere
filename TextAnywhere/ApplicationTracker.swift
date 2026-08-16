//
//  Created by ktiays on 2026/7/10.
//  Copyright (c) 2026 ktiays. All rights reserved.
//

import AppKit
import ApplicationServices
import Observation

struct TargetApplication: Identifiable, Equatable {

    let processIdentifier: pid_t
    let bundleIdentifier: String?
    let localizedName: String

    var id: pid_t { processIdentifier }

    var icon: NSImage? {
        NSRunningApplication(processIdentifier: processIdentifier)?.icon
    }
}

struct TargetWindow: Equatable {

    let processIdentifier: pid_t
    let element: AXUIElement

    static func == (lhs: TargetWindow, rhs: TargetWindow) -> Bool {
        lhs.processIdentifier == rhs.processIdentifier && CFEqual(lhs.element, rhs.element)
    }
}

@MainActor
@Observable
final class ApplicationTracker {

    private(set) var runningApplications: [TargetApplication] = []
    private(set) var lastExternalApplication: TargetApplication?

    private var observers: [NSObjectProtocol] = []
    private var rememberedWindows: [WindowBindingKey: TargetWindow] = [:]
    private let workspace: NSWorkspace
    private let ownBundleIdentifier: String?

    init(
        workspace: NSWorkspace = .shared,
        ownBundleIdentifier: String? = Bundle.main.bundleIdentifier
    ) {
        self.workspace = workspace
        self.ownBundleIdentifier = ownBundleIdentifier
    }

    isolated deinit {
        let notificationCenter = workspace.notificationCenter
        observers.forEach(notificationCenter.removeObserver)
    }

    func start() {
        refreshRunningApplications()
        updateLastExternalApplication(from: workspace.frontmostApplication)

        let notificationCenter = workspace.notificationCenter
        observers.append(
            notificationCenter.addObserver(
                forName: NSWorkspace.didActivateApplicationNotification,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                guard let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                        as? NSRunningApplication else { return }
                Task { @MainActor [weak self] in
                    self?.updateLastExternalApplication(from: application)
                    self?.refreshRunningApplications()
                }
            }
        )
        observers.append(
            notificationCenter.addObserver(
                forName: NSWorkspace.didLaunchApplicationNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.refreshRunningApplications()
                }
            }
        )
        observers.append(
            notificationCenter.addObserver(
                forName: NSWorkspace.didTerminateApplicationNotification,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                    as? NSRunningApplication
                Task { @MainActor [weak self] in
                    if let application {
                        self?.forgetRememberedWindow(for: application)
                    }
                    self?.refreshRunningApplications()
                }
            }
        )
    }

    func preferredTargetApplication() -> TargetApplication? {
        if let frontmostApplication = workspace.frontmostApplication,
           let target = targetApplication(from: frontmostApplication) {
            return target
        }
        return lastExternalApplication
    }

    func refreshRememberedWindow(for application: TargetApplication) {
        guard let window = TargetWindow.currentlyFocused(in: application.processIdentifier) else {
            return
        }
        rememberedWindows[windowKey(for: application)] = window
    }

    func rememberedWindow(for application: TargetApplication) -> TargetWindow? {
        if let window = storedValidWindow(for: application) {
            return window
        }
        refreshRememberedWindow(for: application)
        return storedValidWindow(for: application)
    }

    func refreshRunningApplications() {
        runningApplications = workspace.runningApplications
            .compactMap(targetApplication(from:))
            .sorted {
                $0.localizedName.localizedStandardCompare($1.localizedName) == .orderedAscending
            }
    }

    private func updateLastExternalApplication(from application: NSRunningApplication?) {
        guard let application, let target = targetApplication(from: application) else { return }
        lastExternalApplication = target
        refreshRememberedWindow(for: target)
    }

    private func storedValidWindow(for application: TargetApplication) -> TargetWindow? {
        let key = windowKey(for: application)
        guard let window = rememberedWindows[key] else { return nil }
        guard window.processIdentifier == application.processIdentifier, window.isValid else {
            rememberedWindows.removeValue(forKey: key)
            return nil
        }
        return window
    }

    private func forgetRememberedWindow(for application: NSRunningApplication) {
        if let bundleIdentifier = application.bundleIdentifier {
            rememberedWindows.removeValue(forKey: .bundleIdentifier(bundleIdentifier))
        }
        rememberedWindows.removeValue(forKey: .processIdentifier(application.processIdentifier))
    }

    private func windowKey(for application: TargetApplication) -> WindowBindingKey {
        if let bundleIdentifier = application.bundleIdentifier {
            return .bundleIdentifier(bundleIdentifier)
        }
        return .processIdentifier(application.processIdentifier)
    }

    private func targetApplication(from application: NSRunningApplication) -> TargetApplication? {
        guard !application.isTerminated,
              application.activationPolicy == .regular,
              application.bundleIdentifier != ownBundleIdentifier,
              let localizedName = application.localizedName else {
            return nil
        }
        return TargetApplication(
            processIdentifier: application.processIdentifier,
            bundleIdentifier: application.bundleIdentifier,
            localizedName: localizedName
        )
    }
}

private enum WindowBindingKey: Hashable {

    case bundleIdentifier(String)
    case processIdentifier(pid_t)
}
