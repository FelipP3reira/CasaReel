// Service contracts implemented by the infrastructure packages.
// They stay empty until the corresponding prompt (P03, P04, P06, P07, P10) defines their API.

/// Secure storage for secrets (implemented by `SecurityKit` on top of the Keychain).
public protocol SecureStore: Sendable {}

/// Typed HTTP client for the CasaReel API (implemented by `Networking`).
public protocol APIClient: Sendable {}

/// Photo validation, sanitization and upload (implemented by `MediaKit`).
public protocol MediaProcessor: Sendable {}

/// On-device video composition and export (implemented by `VideoEngine`).
public protocol VideoRenderer: Sendable {}

/// Local persistence for drafts, upload queue and cache (implemented by `Persistence`).
public protocol LocalStore: Sendable {}
