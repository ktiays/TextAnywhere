//
//  Created by ktiays on 2026/7/10.
//  Copyright (c) 2026 ktiays. All rights reserved.
//

import AppKit
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

@MainActor
@Observable
final class ApplicationTracker {

    private(set) var runningApplications: [TargetApplication] = []
    private(set) var lastExternalApplication: TargetApplication?

    private var observers: [NSObjectProtocol] = []
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
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
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
