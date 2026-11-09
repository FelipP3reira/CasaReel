// Service contracts implemented by the infrastructure packages.
// They stay empty until the corresponding prompt (P06, P07, P10) defines their API.
// Security contracts live in `Security/`, the API client in `API/`.

/// Photo validation, sanitization and upload (implemented by `MediaKit`).
public protocol MediaProcessor: Sendable {}

/// On-device video composition and export (implemented by `VideoEngine`).
public protocol VideoRenderer: Sendable {}

/// Local persistence for drafts, upload queue and cache (implemented by `Persistence`).
public protocol LocalStore: Sendable {}
