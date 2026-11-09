// Service contracts implemented by the infrastructure packages.
// They stay empty until the corresponding prompt (P06) defines their API.
// Security contracts live in `Security/`, the API client in `API/`, photo and video contracts in `Media/`.

/// Local persistence for drafts, upload queue and cache (implemented by `Persistence`).
public protocol LocalStore: Sendable {}
