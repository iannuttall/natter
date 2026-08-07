import AppKit
import Foundation
import ServiceManagement

func writeError(_ message: String) {
    FileHandle.standardError.write(Data((message + "\n").utf8))
}

func loginStatusText(_ status: SMAppService.Status) -> String {
    switch status {
    case .enabled: "enabled"
    case .notRegistered: "not-registered"
    case .notFound: "not-found"
    case .requiresApproval: "requires-approval"
    @unknown default: "unknown"
    }
}

let arguments = CommandLine.arguments

if arguments.contains("--login-status") {
    print(loginStatusText(SMAppService.mainApp.status))
} else if arguments.contains("--enable-login") {
    do {
        if SMAppService.mainApp.status != .enabled {
            try SMAppService.mainApp.register()
        }
        print(loginStatusText(SMAppService.mainApp.status))
    } catch {
        writeError("Failed to enable Open at Login: \(error.localizedDescription)")
        exit(1)
    }
} else if arguments.contains("--disable-login") {
    do {
        if SMAppService.mainApp.status == .enabled {
            try SMAppService.mainApp.unregister()
        }
        print(loginStatusText(SMAppService.mainApp.status))
    } catch {
        writeError("Failed to disable Open at Login: \(error.localizedDescription)")
        exit(1)
    }
} else {
    let application = NSApplication.shared
    let delegate = AppDelegate()
    application.delegate = delegate
    application.run()
}
