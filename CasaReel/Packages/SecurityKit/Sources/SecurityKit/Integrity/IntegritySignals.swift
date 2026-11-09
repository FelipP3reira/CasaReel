import Darwin
import Foundation
import MachO

/// A heuristic hint that the device or process may be compromised.
public enum IntegritySignal: String, Sendable, CaseIterable, Comparable {
    case jailbreakFiles = "files"
    case sandboxEscape = "sandbox"
    case injectedLibraries = "dylib"
    case debugger = "debugger"
    case simulator = "simulator"

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// Collects jailbreak / instrumentation / debugger signals to send to the server as risk (`X-Device-Risk`).
///
/// Limitations: every check here runs in a process the attacker controls and can be hooked or patched
/// (Frida, Substitute, rootless jailbreaks hide files). The result is only a risk hint for the server;
/// the app never blocks on it, and App Attest is the stronger signal.
public struct IntegritySignals: Sendable {
    public static let headerName = "X-Device-Risk"

    /// System inputs, injectable so the checks are testable on a clean Simulator.
    public struct Environment: Sendable {
        var isSimulator: Bool
        var fileExists: @Sendable (String) -> Bool
        var canWriteOutsideSandbox: @Sendable () -> Bool
        var loadedImageNames: @Sendable () -> [String]
        var isDebuggerAttached: @Sendable () -> Bool
    }

    static let jailbreakPaths = [
        "/Applications/Cydia.app",
        "/Applications/Sileo.app",
        "/var/jb",
        "/Library/MobileSubstrate/MobileSubstrate.dylib",
        "/usr/sbin/sshd",
        "/bin/bash",
        "/etc/apt",
        "/private/var/lib/apt",
    ]

    static let suspiciousImageMarkers = [
        "frida", "substrate", "substitute", "cycript", "libhooker", "ellekit", "sslkillswitch", "tweakinject",
    ]

    private let environment: Environment

    public init() {
        self.init(environment: .live)
    }

    init(environment: Environment) {
        self.environment = environment
    }

    public func collect() -> [IntegritySignal] {
        var signals: Set<IntegritySignal> = []
        if environment.isSimulator {
            // The Simulator shares the Mac's filesystem (/bin/bash exists), so file checks would be noise.
            signals.insert(.simulator)
        } else {
            if Self.jailbreakPaths.contains(where: environment.fileExists) { signals.insert(.jailbreakFiles) }
            if environment.canWriteOutsideSandbox() { signals.insert(.sandboxEscape) }
        }
        let images = environment.loadedImageNames().map { $0.lowercased() }
        if images.contains(where: { image in Self.suspiciousImageMarkers.contains { image.contains($0) } }) {
            signals.insert(.injectedLibraries)
        }
        if environment.isDebuggerAttached() { signals.insert(.debugger) }
        return signals.sorted()
    }

    /// Compact, PII-free header value, e.g. `v1;none` or `v1;debugger,dylib`.
    public static func headerValue(for signals: [IntegritySignal]) -> String {
        let list = signals.isEmpty ? "none" : signals.sorted().map(\.rawValue).joined(separator: ",")
        return "v1;\(list)"
    }
}

extension IntegritySignals.Environment {
    static let live = Self(
        isSimulator: {
            #if targetEnvironment(simulator)
            true
            #else
            false
            #endif
        }(),
        fileExists: { FileManager.default.fileExists(atPath: $0) },
        canWriteOutsideSandbox: {
            let path = "/private/casareel-\(UUID().uuidString)"
            do {
                try Data().write(to: URL(fileURLWithPath: path))
                try? FileManager.default.removeItem(atPath: path)
                return true
            } catch {
                return false
            }
        },
        loadedImageNames: {
            (0..<_dyld_image_count()).compactMap { index in
                _dyld_get_image_name(index).map { String(cString: $0) }
            }
        },
        isDebuggerAttached: {
            var info = kinfo_proc()
            var size = MemoryLayout<kinfo_proc>.stride
            var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
            guard sysctl(&mib, u_int(mib.count), &info, &size, nil, 0) == 0 else { return false }
            return info.kp_proc.p_flag & P_TRACED != 0
        }
    )
}
