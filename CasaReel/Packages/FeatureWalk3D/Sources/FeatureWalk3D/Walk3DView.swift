import AVKit
import CoreTransferable
import DesignSystem
import Photos
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers
import Walk3DKit

/// Walk 3D: real 3D from the host's own photos and videos, rebuilt for free on their Mac.
public struct Walk3DView: View {
    let model: Walk3DModel
    @State private var picked: [PhotosPickerItem] = []
    @State private var isImporting = false
    @State private var isShowingGuide = false
    /// Not sensitive: only whether the tutorial was already shown on this device.
    @AppStorage("walk3d.recordingGuideSeen") private var guideSeen = false

    public init(model: Walk3DModel) {
        self.model = model
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.large) {
                Text(walkString("Transforme fotos e vídeos da casa em um vídeo andando pelos cômodos em 3D de verdade."))
                    .font(DSFont.body)
                    .foregroundStyle(DSColor.textSecondary)
                mediaStep
                macStep
                videoStep
            }
            .padding(Spacing.medium)
        }
        .background(DSColor.background)
        .fileImporter(isPresented: $isImporting, allowedContentTypes: [Self.archiveType]) { result in
            if case .success(let url) = result { model.renderPackage(at: url) }
        }
        .onChange(of: picked) { load(picked) }
        .sheet(isPresented: $isShowingGuide) {
            RecordingGuideView(kind: .video3D) {
                guideSeen = true
                isShowingGuide = false
            }
            .presentationDragIndicator(.visible)
        }
        .task {
            if !guideSeen { isShowingGuide = true }
        }
    }

    static let archiveType = UTType(filenameExtension: "aar") ?? .data

    // MARK: - Step 1

    private var mediaStep: some View {
        Card {
            VStack(alignment: .leading, spacing: Spacing.small) {
                StepTitle(number: 1, title: walkString("Escolha fotos e vídeos"))
                Text(walkString("Use vídeos filmados andando devagar pelos cômodos, com o celular na altura do peito. Evite pessoas, espelhos e documentos à vista."))
                    .font(DSFont.caption)
                    .foregroundStyle(DSColor.textSecondary)
                Button { isShowingGuide = true } label: {
                    Label { Text(walkString("Como gravar (tutorial)")) } icon: { Image(systemName: "play.rectangle.on.rectangle") }
                        .frame(minHeight: TouchTarget.minimum)
                }
                PhotosPicker(selection: $picked, maxSelectionCount: SceneExporter.maxPhotos + 10,
                             matching: .any(of: [.images, .videos]),
                             // The original file as is: `.automatic` may transcode a long HEVC video first.
                             preferredItemEncoding: .current, photoLibrary: .shared()) {
                    Label { Text(walkString("Escolher na galeria")) } icon: { Image(systemName: "photo.stack") }
                        .frame(maxWidth: .infinity, minHeight: TouchTarget.minimum)
                }
                .buttonStyle(.bordered)
                switch model.media {
                case .empty:
                    EmptyView()
                case .loading:
                    HStack { ProgressView(); Text(walkString("Carregando…")) }
                case .ready(let photos, let videos):
                    Text(walkString("\(photos) fotos e \(videos) vídeos selecionados"))
                        .font(DSFont.callout)
                case .failed:
                    ErrorBanner(walkString("Não foi possível abrir os itens escolhidos."))
                }
                exportControls
            }
        }
    }

    @ViewBuilder
    private var exportControls: some View {
        switch model.exportState {
        case .idle:
            PrimaryButton(walkString("Preparar pacote para o Mac"), systemImage: "shippingbox") { model.exportScene() }
                .disabled(!model.canExport)
        case .exporting(let progress):
            HStack(spacing: Spacing.medium) {
                ProgressRing(progress: progress).frame(width: 48, height: 48)
                Text(walkString("Separando os melhores quadros…")).font(DSFont.callout)
                Spacer()
                Button(role: .cancel) { model.cancelExport() } label: { Text(walkString("Cancelar")) }
            }
        case .exported(let result):
            Label { Text(walkString("Pacote pronto: \(result.photoCount) fotos e \(result.frameCount) quadros de vídeo")) } icon: {
                Image(systemName: "checkmark.seal.fill")
            }
            .font(DSFont.callout)
            .foregroundStyle(DSColor.success)
            ShareLink(item: result.archiveURL) {
                Label { Text(walkString("Enviar para o Mac")) } icon: { Image(systemName: "airplayaudio") }
                    .frame(maxWidth: .infinity, minHeight: TouchTarget.minimum)
            }
            .buttonStyle(.borderedProminent)
        case .failed(let error):
            ErrorBanner(error.message) { model.exportScene() }
        }
    }

    // MARK: - Step 2

    private var macStep: some View {
        Card {
            VStack(alignment: .leading, spacing: Spacing.small) {
                StepTitle(number: 2, title: walkString("Monte o 3D no Mac"))
                Text(walkString("No Mac, rode o script walk3d.sh com o pacote. Ele usa programas gratuitos (COLMAP e Brush) e leva de 30 minutos a 2 horas. No fim, ele cria um arquivo terminado em -3D.aar: envie-o de volta para o iPhone por AirDrop e salve em Arquivos."))
                    .font(DSFont.caption)
                    .foregroundStyle(DSColor.textSecondary)
            }
        }
    }

    // MARK: - Step 3

    private var videoStep: some View {
        Card {
            VStack(alignment: .leading, spacing: Spacing.small) {
                StepTitle(number: 3, title: walkString("Gere o vídeo andando"))
                switch model.renderState {
                case .idle:
                    PrimaryButton(walkString("Importar 3D"), systemImage: "cube.transparent") { isImporting = true }
                case .rendering(let progress, let pausedForHeat):
                    HStack(spacing: Spacing.medium) {
                        ProgressRing(progress: progress).frame(width: 48, height: 48)
                        Text(pausedForHeat ? walkString("O aparelho esquentou. Continua assim que esfriar.") : walkString("Gerando o vídeo em 3D…"))
                            .font(DSFont.callout)
                        Spacer()
                        Button(role: .cancel) { model.cancelRender() } label: { Text(walkString("Cancelar")) }
                    }
                case .finished(let video):
                    FinishedVideo(video: video)
                    SecondaryButton(walkString("Importar outro 3D"), systemImage: "cube.transparent") { isImporting = true }
                case .failed(let error):
                    ErrorBanner(error.message) { isImporting = true }
                }
                if model.watermark {
                    Text(walkString("No plano grátis o vídeo sai com a marca d'água CasaReel."))
                        .font(DSFont.caption)
                        .foregroundStyle(DSColor.textSecondary)
                }
            }
        }
    }

    // MARK: - Loading picked items

    private func load(_ items: [PhotosPickerItem]) {
        model.loadMedia(count: items.count) { index in
            let item = items[index]
            if item.supportedContentTypes.contains(where: { $0.conforms(to: .movie) }) {
                return (try? await item.loadTransferable(type: PickedMovie.self)).flatMap { $0 }.map { .video($0.url) }
            }
            return (try? await item.loadTransferable(type: PickedImage.self)).flatMap { $0 }.map { .photo($0.url) }
        }
    }
}

private struct StepTitle: View {
    let number: Int
    let title: LocalizedStringResource

    var body: some View {
        HStack(spacing: Spacing.small) {
            Text("\(number)")
                .font(DSFont.headline)
                .foregroundStyle(DSColor.onAccent)
                .frame(width: 28, height: 28)
                .background(Circle().fill(DSColor.accent))
                .accessibilityHidden(true)
            Text(title).font(DSFont.headline)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct FinishedVideo: View {
    let video: Walk3DVideo
    @State private var player: AVPlayer?
    @State private var savedMessage: LocalizedStringResource?

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.small) {
            VideoPlayer(player: player)
                .aspectRatio(9 / 16, contentMode: .fit)
                .frame(maxHeight: 420)
                .clipShape(RoundedRectangle(cornerRadius: Radius.medium))
                .onAppear { player = AVPlayer(url: video.fileURL) }
            ShareLink(item: video.fileURL) {
                Label { Text(walkString("Compartilhar")) } icon: { Image(systemName: "square.and.arrow.up") }
                    .frame(maxWidth: .infinity, minHeight: TouchTarget.minimum)
            }
            .buttonStyle(.borderedProminent)
            SecondaryButton(walkString("Salvar na galeria"), systemImage: "photo.on.rectangle") {
                Task { savedMessage = await Self.save(video.fileURL) }
            }
            if let savedMessage { Text(savedMessage).font(DSFont.callout).foregroundStyle(DSColor.textSecondary) }
        }
    }

    /// Asks for add-only access at the moment the user saves, never before.
    private static func save(_ url: URL) async -> LocalizedStringResource {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            return walkString("Sem permissão para salvar. Ative em Ajustes > CasaReel > Fotos.")
        }
        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetCreationRequest.creationRequestForAssetFromVideo(atFileURL: url)
            }
            return walkString("Vídeo salvo na galeria.")
        } catch {
            return walkString("Não foi possível salvar o vídeo.")
        }
    }
}

// MARK: - Picked files

/// The original file of a picked photo, streamed to disk; the picker runs out of process,
/// so no photo-library permission is needed to read.
struct PickedImage: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .image) { PickedImage(url: try Inbox.keep($0.file)) }
    }
}

/// Same for videos, which can be large: never loaded in memory.
struct PickedMovie: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .movie) { PickedMovie(url: try Inbox.keep($0.file)) }
    }
}

enum Inbox {
    /// The received file is only valid inside the transfer closure: copy it somewhere the app owns.
    static func keep(_ file: URL) throws -> URL {
        let inbox = FileManager.default.temporaryDirectory.appending(path: "CasaReelWalk3DInbox", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true,
                                                attributes: [.protectionKey: FileProtectionType.completeUnlessOpen])
        let copy = inbox.appending(path: UUID().uuidString).appendingPathExtension(file.pathExtension)
        try FileManager.default.copyItem(at: file, to: copy)
        return copy
    }
}

// MARK: - Messages

extension SceneExportError {
    var message: LocalizedStringResource {
        switch self {
        case .noMedia: walkString("Escolha pelo menos uma foto ou um vídeo.")
        case .notEnoughImages: walkString("Poucas imagens para montar o 3D. Adicione um vídeo andando pelos cômodos.")
        case .unreadableMedia: walkString("Um dos vídeos não pôde ser lido.")
        case .insufficientStorage: walkString("Pouco espaço livre no iPhone.")
        case .writeFailed, .cancelled: walkString("Não foi possível preparar o pacote.")
        }
    }
}

extension Walk3DRenderError {
    var message: LocalizedStringResource {
        switch self {
        case .invalidPackage: walkString("Esse arquivo não é um 3D gerado pelo script do CasaReel.")
        case .gpuUnavailable: walkString("Não foi possível desenhar o 3D neste aparelho.")
        case .overheated: walkString("O aparelho esquentou demais. Tente de novo em alguns minutos.")
        case .writerFailed, .cancelled: walkString("Não foi possível gerar o vídeo.")
        }
    }
}

func walkString(_ key: String.LocalizationValue) -> LocalizedStringResource {
    LocalizedStringResource(key, bundle: .atURL(Bundle.module.bundleURL))
}
