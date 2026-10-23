//
//  Created by ktiays on 2026/10/24.
//  Copyright (c) 2026 ktiays. All rights reserved.
//

import AppKit
import Observation

@MainActor
@Observable
final class UpdateController {

    enum Activity {
        case idle
        case checking
        case installing
    }

    private static let automaticCheckInterval: TimeInterval = 24 * 60 * 60

    let currentVersionDescription: String
    private(set) var activity = Activity.idle

    private let settings: AppSettings
    private let checker: UpdateChecker
    private let installer: UpdateInstaller
    private let currentVersion: SemanticVersion?
    private var schedulingTask: Task<Void, Never>?

    init(
        settings: AppSettings,
        checker: UpdateChecker = UpdateChecker(),
        installer: UpdateInstaller = UpdateInstaller()
    ) {
        self.settings = settings
        self.checker = checker
        self.installer = installer
        currentVersionDescription = Bundle.main
            .object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown"
        currentVersion = SemanticVersion(currentVersionDescription)
    }

    var isBusy: Bool {
        activity != .idle
    }

    var lastCheckDate: Date? {
        settings.lastUpdateCheckDate
    }

    func start() {
        // Debug builds skip automatic checks so development builds aren't offered release updates.
        #if !DEBUG
        guard schedulingTask == nil else { return }
        schedulingTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(10))
            while !Task.isCancelled {
                await self?.checkInBackgroundIfDue()
                try? await Task.sleep(for: .seconds(60 * 60))
            }
        }
        #endif
    }

    func checkForUpdates() {
        guard !isBusy else { return }
        Task {
            await check(isUserInitiated: true)
        }
    }

    private func checkInBackgroundIfDue() async {
        guard settings.isAutomaticUpdateCheckEnabled, !isBusy else { return }
        if let lastCheckDate = settings.lastUpdateCheckDate,
           Date.now.timeIntervalSince(lastCheckDate) < Self.automaticCheckInterval {
            return
        }
        await check(isUserInitiated: false)
    }

    private func check(isUserInitiated: Bool) async {
        guard let currentVersion else {
            if isUserInitiated {
                presentCheckFailure(SoftwareUpdateError.invalidResponse)
            }
            return
        }

        activity = .checking
        let update: AvailableUpdate?
        do {
            update = try await checker.availableUpdate(newerThan: currentVersion)
            settings.lastUpdateCheckDate = .now
            activity = .idle
        } catch {
            activity = .idle
            if isUserInitiated {
                presentCheckFailure(error)
            }
            return
        }

        guard let update else {
            if isUserInitiated {
                presentUpToDate()
            }
            return
        }
        if !isUserInitiated, settings.skippedUpdateVersion == update.version.description {
            return
        }
        await promptToInstall(update)
    }

    private func promptToInstall(_ update: AvailableUpdate) async {
        let alert = NSAlert()
        alert.messageText = "TextAnywhere \(update.version) Is Available"
        alert.informativeText = "You have version \(currentVersionDescription). TextAnywhere will quit and reopen to finish installing."
        alert.accessoryView = releaseNotesLink(to: update.releasePageURL)
        alert.addButton(withTitle: "Install and Relaunch")
        alert.addButton(withTitle: "Later")
        alert.addButton(withTitle: "Skip This Version")

        switch runModal(alert) {
        case .alertFirstButtonReturn:
            await install(update)
        case .alertThirdButtonReturn:
            settings.skippedUpdateVersion = update.version.description
        default:
            break
        }
    }

    private func install(_ update: AvailableUpdate) async {
        activity = .installing
        do {
            try installer.validateInstallLocation()
            let stagedUpdate = try await installer.stageUpdate(update)
            defer {
                try? FileManager.default.removeItem(at: stagedUpdate.stagingDirectoryURL)
            }
            try installer.install(stagedAppURL: stagedUpdate.appURL)
        } catch {
            activity = .idle
            presentInstallFailure(error, releasePageURL: update.releasePageURL)
            return
        }

        do {
            try installer.relaunch()
        } catch {
            activity = .idle
            let alert = NSAlert()
            alert.messageText = "Update Installed"
            alert.informativeText = "TextAnywhere couldn't reopen itself. Quit and open it again to use the new version."
            runModal(alert)
        }
    }

    private func presentUpToDate() {
        let alert = NSAlert()
        alert.messageText = "You're Up to Date"
        alert.informativeText = "TextAnywhere \(currentVersionDescription) is the latest version."
        runModal(alert)
    }

    private func presentCheckFailure(_ error: any Error) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Couldn't Check for Updates"
        alert.informativeText = error.localizedDescription
        runModal(alert)
    }

    private func presentInstallFailure(_ error: any Error, releasePageURL: URL) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Couldn't Install the Update"
        alert.informativeText = error.localizedDescription
        alert.addButton(withTitle: "Download Manually")
        alert.addButton(withTitle: "Cancel")
        if runModal(alert) == .alertFirstButtonReturn {
            NSWorkspace.shared.open(releasePageURL)
        }
    }

    private func releaseNotesLink(to url: URL) -> NSTextField {
        let label = NSTextField(
            labelWithAttributedString: NSAttributedString(
                string: "View Release Notes",
                attributes: [
                    .link: url,
                    .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
                ]
            )
        )
        label.isSelectable = true
        label.allowsEditingTextAttributes = true
        label.sizeToFit()
        return label
    }

    @discardableResult
    private func runModal(_ alert: NSAlert) -> NSApplication.ModalResponse {
        NSApp.activate()
        return alert.runModal()
    }
}
