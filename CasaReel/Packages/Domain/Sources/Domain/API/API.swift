import Foundation

/// Phase 1 endpoints of openapi.yaml. Creations carry an `Idempotency-Key`; sensitive routes require App Attest.
public enum API {
    // MARK: Auth

    public static func signInWithApple(_ request: AppleLoginRequest) -> Endpoint<TokenPair> {
        Endpoint(name: "auth.apple", method: .post, path: ["auth", "apple"], body: request,
                 requiresAuth: false, requiresAttest: true)
    }

    public static func refresh(refreshToken: String) -> Endpoint<TokenPair> {
        Endpoint(name: "auth.refresh", method: .post, path: ["auth", "refresh"],
                 body: RefreshRequest(refreshToken: refreshToken), requiresAuth: false)
    }

    public static func signOut(allSessions: Bool = false) -> Endpoint<EmptyResponse> {
        Endpoint(name: "auth.logout", method: .post, path: ["auth", "logout"],
                 query: allSessions ? [URLQueryItem(name: "all", value: "true")] : [])
    }

    public static func attestChallenge() -> Endpoint<AttestChallenge> {
        Endpoint(name: "attest.challenge", method: .post, path: ["attest", "challenge"], requiresAuth: false)
    }

    /// The spec marks this route as authenticated, but `/auth/apple` needs an attested key first.
    /// Sent without a session until the backend resolves it (see Packages/Networking/README.md).
    public static func attestRegister(keyId: String, attestationObject: Data, challenge: String) -> Endpoint<EmptyResponse> {
        Endpoint(
            name: "attest.register", method: .post, path: ["attest", "register"],
            body: AttestRegistration(keyId: keyId, attestationObject: attestationObject.base64EncodedString(), challenge: challenge),
            requiresAuth: false
        )
    }

    // MARK: Account

    public static func me() -> Endpoint<User> {
        Endpoint(name: "me.get", method: .get, path: ["me"])
    }

    public static func deleteAccount() -> Endpoint<AccountDeletion> {
        Endpoint(name: "me.delete", method: .delete, path: ["me"], requiresAttest: true)
    }

    public static func requestDataExport() -> Endpoint<EmptyResponse> {
        Endpoint(name: "me.export", method: .post, path: ["me", "export"], requiresAttest: true, idempotent: true)
    }

    public static func consents() -> Endpoint<[Consent]> {
        Endpoint(name: "me.consents", method: .get, path: ["me", "consents"])
    }

    public static func updateConsent(_ update: ConsentUpdate) -> Endpoint<EmptyResponse> {
        Endpoint(name: "me.consents.update", method: .put, path: ["me", "consents"], body: update)
    }

    public static func entitlements() -> Endpoint<Entitlements> {
        Endpoint(name: "me.entitlements", method: .get, path: ["me", "entitlements"])
    }

    // MARK: Properties

    public static func properties(cursor: String? = nil, limit: Int = 25) -> Endpoint<Page<Property>> {
        var query = [URLQueryItem(name: "limit", value: String(min(max(limit, 1), 100)))]
        if let cursor { query.append(URLQueryItem(name: "cursor", value: cursor)) }
        return Endpoint(name: "properties.list", method: .get, path: ["properties"], query: query)
    }

    public static func createProperty(_ property: PropertyCreate) -> Endpoint<Property> {
        Endpoint(name: "properties.create", method: .post, path: ["properties"], body: property, idempotent: true)
    }

    public static func property(_ id: UUID) -> Endpoint<Property> {
        Endpoint(name: "properties.get", method: .get, path: ["properties", .id(id)])
    }

    public static func updateProperty(_ id: UUID, _ update: PropertyUpdate) -> Endpoint<Property> {
        Endpoint(name: "properties.update", method: .patch, path: ["properties", .id(id)], body: update)
    }

    public static func deleteProperty(_ id: UUID) -> Endpoint<EmptyResponse> {
        Endpoint(name: "properties.delete", method: .delete, path: ["properties", .id(id)])
    }

    // MARK: Media

    public struct UploadIntents: Decodable, Sendable {
        public let intents: [UploadIntent]
    }

    struct UploadIntentBatch: Encodable, Sendable {
        let files: [UploadIntentRequest]
    }

    public static func uploadIntents(propertyId: UUID, files: [UploadIntentRequest]) -> Endpoint<UploadIntents> {
        Endpoint(name: "media.uploadIntents", method: .post, path: ["properties", .id(propertyId), "photos", "upload-intents"],
                 body: UploadIntentBatch(files: files), idempotent: true)
    }

    public static func completeUpload(mediaId: UUID) -> Endpoint<MediaAsset> {
        Endpoint(name: "media.complete", method: .post, path: ["media", .id(mediaId), "complete"])
    }

    public static func media(propertyId: UUID) -> Endpoint<[MediaAsset]> {
        Endpoint(name: "media.list", method: .get, path: ["properties", .id(propertyId), "media"],
                 query: [URLQueryItem(name: "kind", value: "photo")])
    }

    public struct MediaUpdate: Encodable, Sendable {
        public let position: Int?
        public let roomType: String?

        public init(position: Int? = nil, roomType: String? = nil) {
            self.position = position
            self.roomType = roomType
        }
    }

    public static func updateMedia(_ id: UUID, _ update: MediaUpdate) -> Endpoint<MediaAsset> {
        Endpoint(name: "media.update", method: .patch, path: ["media", .id(id)], body: update)
    }

    public static func deleteMedia(_ id: UUID) -> Endpoint<EmptyResponse> {
        Endpoint(name: "media.delete", method: .delete, path: ["media", .id(id)])
    }

    // MARK: Templates, jobs and outputs

    public static func templates() -> Endpoint<[TemplateSummary]> {
        Endpoint(name: "templates.list", method: .get, path: ["templates"])
    }

    public static func createJob(propertyId: UUID, _ job: JobCreate) -> Endpoint<Job> {
        Endpoint(name: "jobs.create", method: .post, path: ["properties", .id(propertyId), "jobs"],
                 body: job, requiresAttest: true, idempotent: true)
    }

    public static func job(_ id: UUID) -> Endpoint<Job> {
        Endpoint(name: "jobs.get", method: .get, path: ["jobs", .id(id)])
    }

    public static func cancelJob(_ id: UUID) -> Endpoint<EmptyResponse> {
        Endpoint(name: "jobs.cancel", method: .delete, path: ["jobs", .id(id)])
    }

    public struct RegisteredVideo: Decodable, Sendable {
        public let output: Output
        public let upload: UploadIntent
    }

    public static func registerLocalVideo(propertyId: UUID, _ video: LocalVideoRegister) -> Endpoint<RegisteredVideo> {
        Endpoint(name: "videos.register", method: .post, path: ["properties", .id(propertyId), "videos"],
                 body: video, idempotent: true)
    }

    public static func outputs(propertyId: UUID) -> Endpoint<[Output]> {
        Endpoint(name: "outputs.list", method: .get, path: ["properties", .id(propertyId), "outputs"])
    }

    public static func downloadURL(outputId: UUID) -> Endpoint<DownloadURL> {
        Endpoint(name: "outputs.downloadURL", method: .get, path: ["outputs", .id(outputId), "download-url"])
    }
}
