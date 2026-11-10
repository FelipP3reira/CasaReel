import DesignSystem
import Domain
import FeaturePhotos
import FeatureVideo
import SwiftUI

/// The video project being edited, shared by the "Criar" tab screens.
@Observable
@MainActor
final class EditorSession {
    private(set) var model: VideoEditorModel?
    /// A draft saved by an earlier session, offered for resuming.
    private(set) var savedDraft: VideoDraft?

    func start(_ model: VideoEditorModel) {
        self.model = model
        savedDraft = nil
    }

    func refreshSavedDraft(from store: any VideoDraftStoring) async {
        guard model == nil else { return }
        savedDraft = await store.load()
    }

    func close() {
        model?.cancelRendering()
        model = nil
        savedDraft = nil
    }
}

/// Step zero: pick photos, or resume the saved draft.
struct PhotoPickerScreen: View {
    let router: Router
    let selection: PhotoSelectionModel
    let editor: EditorSession
    let environment: AppEnvironment

    var body: some View {
        VStack(spacing: 0) {
            if let draft = editor.savedDraft {
                Card {
                    VStack(alignment: .leading, spacing: Spacing.small) {
                        Label("Você tem um vídeo em andamento", systemImage: "doc.badge.clock")
                            .font(DSFont.headline)
                        Text("\(draft.scenes.count) cenas, salvo \(draft.updatedAt.formatted(.relative(presentation: .named)))")
                            .font(DSFont.caption)
                            .foregroundStyle(DSColor.textSecondary)
                        PrimaryButton("Retomar rascunho") { resume(draft) }
                    }
                }
                .padding(Spacing.medium)
            }
            PhotoSelectionView(model: selection) { photos in
                editor.start(makeEditor(photos: photos))
                router.push(.videoEditor)
            }
        }
        .background(DSColor.background)
        .navigationTitle(Text("Escolha as fotos"))
        .task { await editor.refreshSavedDraft(from: environment.drafts) }
    }

    private func makeEditor(photos: [PreparedPhoto]) -> VideoEditorModel {
        let analyses = Dictionary(selection.items.compactMap { item -> (UUID, AnalysisResult)? in
            guard case .ready(let photo) = item.state, let analysis = item.analysis else { return nil }
            return (photo.id, analysis)
        }, uniquingKeysWith: { first, _ in first })
        // Local mode: no account yet, so the free plan applies (watermark on, premium templates locked).
        return VideoEditorModel(
            photos: photos, analyses: analyses, renderer: environment.videoRenderer, drafts: environment.drafts,
            power: environment.power, isPro: false, watermark: true, captionForRoom: RoomName.localized
        )
    }

    private func resume(_ draft: VideoDraft) {
        let missing = draft.photoFiles.contains { !FileManager.default.fileExists(atPath: $0.path) }
        guard !missing else {
            Task { await environment.drafts.delete(); await editor.refreshSavedDraft(from: environment.drafts) }
            return
        }
        editor.start(VideoEditorModel(
            draft: draft, renderer: environment.videoRenderer, drafts: environment.drafts,
            power: environment.power, isPro: false, watermark: true
        ))
        router.push(.videoEditor)
    }
}

struct VideoEditorScreen: View {
    let router: Router
    let editor: EditorSession

    var body: some View {
        Group {
            if let model = editor.model {
                VideoEditorView(model: model) { router.push(.subscription) }
            } else {
                EmptyState(systemImage: "film.stack", title: "Nenhum vídeo em edição",
                           message: "Escolha as fotos na aba Criar para começar.")
            }
        }
        .navigationTitle(Text("Editor de vídeo"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Default captions: the room detected by the on-device analysis.
enum RoomName {
    static func localized(_ room: RoomType) -> String {
        switch room {
        case .facade: String(localized: "Fachada")
        case .livingRoom: String(localized: "Sala")
        case .kitchen: String(localized: "Cozinha")
        case .bedroom: String(localized: "Quarto")
        case .bathroom: String(localized: "Banheiro")
        case .balcony: String(localized: "Varanda")
        case .pool: String(localized: "Piscina")
        case .other: ""
        }
    }
}
