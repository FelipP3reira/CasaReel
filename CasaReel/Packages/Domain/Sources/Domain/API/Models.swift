import Foundation

// Phase 1 schemas from openapi.yaml. Decoding is strict for required fields (a missing one fails)
// and tolerant of new fields (unknown keys are ignored) and of new enum values (`.unknown`).

/// String enums that decode values added by newer API versions as `.unknown` instead of failing.
public protocol ForwardCompatibleEnum: RawRepresentable, Codable, Sendable where RawValue == String {
    static var unknown: Self { get }
}

extension ForwardCompatibleEnum {
    public init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = Self(rawValue: raw) ?? .unknown
    }
}

public struct Page<Item: Decodable & Sendable>: Decodable, Sendable {
    public let items: [Item]
    public let nextCursor: String?
}

// MARK: - Auth and account

public struct AppleLoginRequest: Encodable, Sendable {
    public let identityToken: String
    public let nonce: String
    public let deviceId: String
    public let fullName: String?

    public init(identityToken: String, nonce: String, deviceId: String, fullName: String? = nil) {
        self.identityToken = identityToken
        self.nonce = nonce
        self.deviceId = deviceId
        self.fullName = fullName
    }
}

struct RefreshRequest: Encodable, Sendable {
    let refreshToken: String
}

public struct AttestChallenge: Decodable, Sendable {
    public let challenge: String
    public let expiresAt: Date
}

struct AttestRegistration: Encodable, Sendable {
    let keyId: String
    let attestationObject: String
    let challenge: String
}

public struct User: Decodable, Sendable, Equatable {
    public let id: UUID
    public let email: String?
    public let displayName: String?
    public let locale: String
    public let status: String
    public let createdAt: Date
}

public struct AccountDeletion: Decodable, Sendable, Equatable {
    public let purgeAfter: Date
}

public enum ConsentPurpose: String, Codable, Sendable, CaseIterable {
    case terms
    case privacyPolicy = "privacy_policy"
    case marketing
    case analytics
    case aiImprovement = "ai_improvement"
}

public struct Consent: Decodable, Sendable, Equatable {
    public let purpose: ConsentPurpose
    public let version: String
    public let grantedAt: Date
    public let revokedAt: Date?
}

public struct ConsentUpdate: Encodable, Sendable {
    public let purpose: ConsentPurpose
    public let version: String?
    public let granted: Bool

    public init(purpose: ConsentPurpose, version: String?, granted: Bool) {
        self.purpose = purpose
        self.version = version
        self.granted = granted
    }
}

public struct Entitlements: Decodable, Sendable, Equatable {
    public enum Plan: String, ForwardCompatibleEnum {
        case free, pro, manager, unknown
    }

    public struct Limits: Decodable, Sendable, Equatable {
        public let videosPerMonth: Int
        public let photosPerProperty: Int
        public let watermark: Bool
        public let serverRender: Bool
        public let tour3d: Bool
    }

    public let plan: Plan
    public let creditBalance: Int
    public let limits: Limits
    public let currentPeriodEnd: Date?
}

// MARK: - Properties and media

public enum Visibility: String, ForwardCompatibleEnum {
    case `private`, unlisted, `public`, unknown
}

public struct Property: Decodable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public let title: String
    public let cityPublic: String?
    public let visibility: Visibility
    public let createdAt: Date
}

public struct PropertyCreate: Encodable, Sendable {
    public let title: String
    public let cityPublic: String?
    /// Stored encrypted by the server and never shown publicly.
    public let address: String?

    public init(title: String, cityPublic: String? = nil, address: String? = nil) {
        self.title = title
        self.cityPublic = cityPublic
        self.address = address
    }
}

public struct PropertyUpdate: Encodable, Sendable {
    public let title: String?
    public let cityPublic: String?
    public let address: String?
    public let visibility: Visibility?

    public init(title: String? = nil, cityPublic: String? = nil, address: String? = nil, visibility: Visibility? = nil) {
        self.title = title
        self.cityPublic = cityPublic
        self.address = address
        self.visibility = visibility
    }
}

public enum ImageMimeType: String, Codable, Sendable {
    case jpeg = "image/jpeg"
    case heic = "image/heic"
    case png = "image/png"
}

public struct UploadIntentRequest: Encodable, Sendable {
    public let size: Int
    public let mimeType: ImageMimeType
    /// Lowercase hex SHA-256 of the sanitized file.
    public let sha256: String
    public let width: Int?
    public let height: Int?

    public init(size: Int, mimeType: ImageMimeType, sha256: String, width: Int? = nil, height: Int? = nil) {
        self.size = size
        self.mimeType = mimeType
        self.sha256 = sha256
        self.width = width
        self.height = height
    }
}

public struct UploadIntent: Decodable, Sendable, Equatable {
    public let mediaId: UUID
    public let method: String
    public let url: URL
    public let headers: [String: String]
    public let expiresAt: Date
}

public struct MediaAsset: Decodable, Sendable, Equatable, Identifiable {
    public enum Status: String, ForwardCompatibleEnum {
        case pending, uploaded, processing, ready, rejected, expired, unknown
    }

    public struct Analysis: Decodable, Sendable, Equatable {
        public let qualityScore: Double?
        public let blur: Double?
        public let exposure: Double?
        public let warnings: [String]?
    }

    public let id: UUID
    public let kind: String
    public let status: Status
    public let rejectReason: String?
    public let position: Int?
    public let roomType: String?
    public let thumbnailUrl: URL?
    public let analysis: Analysis?
}

// MARK: - Templates, jobs and outputs

public struct TemplateSummary: Decodable, Sendable, Equatable {
    public let slug: TemplateSlug
    public let version: Int
    public let name: String
    public let premium: Bool
    public let previewUrl: URL?
}

public enum JobType: String, ForwardCompatibleEnum {
    case analyzePhotos = "analyze_photos"
    case renderVideo = "render_video"
    case buildTour360 = "build_tour_360"
    case reconstruct3D = "reconstruct_3d"
    case unknown
}

public struct JobCreate: Encodable, Sendable {
    public let type: JobType
    public let templateSlug: TemplateSlug?
    public let mediaIds: [UUID]?

    public init(type: JobType, templateSlug: TemplateSlug? = nil, mediaIds: [UUID]? = nil) {
        self.type = type
        self.templateSlug = templateSlug
        self.mediaIds = mediaIds
    }
}

public struct Job: Decodable, Sendable, Equatable, Identifiable {
    public enum Status: String, ForwardCompatibleEnum {
        case queued, running, retrying, succeeded, failed, canceled, unknown
    }

    public let id: UUID
    public let type: JobType
    public let status: Status
    public let progress: Double
    public let etaSeconds: Int?
    public let errorCode: String?
    public let outputs: [Output]?
    public let queuedAt: Date
    public let finishedAt: Date?
}

public struct LocalVideoRegister: Encodable, Sendable {
    public enum Aspect: String, Encodable, Sendable {
        case vertical = "9:16"
        case horizontal = "16:9"
    }

    public let templateSlug: TemplateSlug
    public let templateVersion: Int
    public let aspect: Aspect
    public let durationMs: Int
    public let sizeBytes: Int
    public let sha256: String
    public let syntheticContent: Bool

    public init(
        templateSlug: TemplateSlug, templateVersion: Int, aspect: Aspect,
        durationMs: Int, sizeBytes: Int, sha256: String, syntheticContent: Bool = false
    ) {
        self.templateSlug = templateSlug
        self.templateVersion = templateVersion
        self.aspect = aspect
        self.durationMs = durationMs
        self.sizeBytes = sizeBytes
        self.sha256 = sha256
        self.syntheticContent = syntheticContent
    }
}

public struct Output: Decodable, Sendable, Equatable, Identifiable {
    public enum Kind: String, ForwardCompatibleEnum {
        case videoVertical = "video_vertical"
        case videoHorizontal = "video_horizontal"
        case thumbnail
        case tour360 = "tour_360"
        case tour3D = "tour_3d"
        case manifest
        case unknown
    }

    public let id: UUID
    public let kind: Kind
    public let durationMs: Int?
    public let sizeBytes: Int?
    public let syntheticContent: Bool
    public let watermark: Bool
    public let createdAt: Date
}

public struct DownloadURL: Decodable, Sendable, Equatable {
    public let url: URL
    public let expiresAt: Date?
}
