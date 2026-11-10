import AVKit
import DesignSystem
import Domain
import Photos
import SwiftUI

/// The four-step editor. `onPaywall` opens the subscription screen for premium templates.
public struct VideoEditorView: View {
    @Bindable private var model: VideoEditorModel
    private let onPaywall: () -> Void
    @Environment(\.scenePhase) private var scenePhase

    public init(model: VideoEditorModel, onPaywall: @escaping () -> Void) {
        self.model = model
        self.onPaywall = onPaywall
    }

    public var body: some View {
        VStack(spacing: 0) {
            StepHeader(step: model.step)
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.medium) {
                    switch model.step {
                    case .template: TemplateStep(model: model)
                    case .script: ScriptStep(model: model)
                    case .customize: CustomizeStep(model: model)
                    case .export: ExportStep(model: model)
                    }
                }
                .padding(Spacing.medium)
            }
            navigation
        }
        .background(DSColor.background)
        .onChange(of: model.paywallRequested) {
            guard model.paywallRequested else { return }
            model.paywallRequested = false
            onPaywall()
        }
        .onChange(of: scenePhase) {
            if scenePhase == .background { Task { await model.saveDraft() } }
        }
    }

    private var navigation: some View {
        HStack(spacing: Spacing.small) {
            if let previous = VideoEditorModel.Step(rawValue: model.step.rawValue - 1) {
                SecondaryButton(videoString("Voltar")) { model.step = previous }
                    .disabled(model.isBusy)
            }
            if let next = VideoEditorModel.Step(rawValue: model.step.rawValue + 1) {
                PrimaryButton(videoString("Avançar")) { model.step = next }
                    .disabled(model.scenes.isEmpty)
            }
        }
        .padding(Spacing.medium)
        .background(DSColor.surface)
    }
}

struct StepHeader: View {
    let step: VideoEditorModel.Step

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xSmall) {
            Text(videoString("Passo \(step.rawValue + 1) de \(VideoEditorModel.Step.allCases.count)"))
                .font(DSFont.caption)
                .foregroundStyle(DSColor.textSecondary)
            Text(step.title)
                .font(DSFont.title)
                .foregroundStyle(DSColor.textPrimary)
                .accessibilityAddTraits(.isHeader)
            ProgressView(value: Double(step.rawValue + 1), total: Double(VideoEditorModel.Step.allCases.count))
                .accessibilityHidden(true)
        }
        .padding(Spacing.medium)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DSColor.surface)
    }
}

// MARK: - Step 1

struct TemplateStep: View {
    let model: VideoEditorModel

    var body: some View {
        ForEach(model.templates) { template in
            Button { model.selectTemplate(template.slug) } label: {
                Card {
                    HStack(spacing: Spacing.medium) {
                        TemplatePreviewIcon(slug: template.slug)
                        VStack(alignment: .leading, spacing: Spacing.xSmall) {
                            HStack {
                                Text(template.displayName).font(DSFont.headline).foregroundStyle(DSColor.textPrimary)
                                if model.isPremium(template) { Tag(videoString("Pro"), style: .warning) }
                            }
                            Text(template.summary).font(DSFont.callout).foregroundStyle(DSColor.textSecondary)
                            Text(template.aspects.map(\.rawValue).joined(separator: " · "))
                                .font(DSFont.caption).foregroundStyle(DSColor.textSecondary)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: model.templateSlug == template.slug ? "checkmark.circle.fill" : "circle")
                            .font(.title2)
                            .foregroundStyle(DSColor.accent)
                            .accessibilityHidden(true)
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(model.templateSlug == template.slug ? [.isSelected, .isButton] : .isButton)
        }
    }
}

/// Lightweight animated hint of the template's motion (static when Reduce Motion is on).
struct TemplatePreviewIcon: View {
    let slug: TemplateSlug
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var animate = false

    var body: some View {
        Image(systemName: symbol)
            .font(.title)
            .foregroundStyle(DSColor.onAccent)
            .frame(width: 56, height: 56)
            .background(RoundedRectangle(cornerRadius: Radius.small).fill(DSColor.accent))
            .scaleEffect(animate ? 1.08 : 1)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) { animate = true }
            }
            .accessibilityHidden(true)
    }

    private var symbol: String {
        switch slug.rawValue {
        case "cinematic-soft": "film"
        case "dynamic-social": "bolt.fill"
        case "walk-tour": "figure.walk"
        default: "sparkles"
        }
    }
}

// MARK: - Step 2

struct ScriptStep: View {
    let model: VideoEditorModel

    var body: some View {
        Text(videoString("Arraste para reordenar. Duração total: \(Self.seconds(model.totalDurationMs))"))
            .font(DSFont.callout)
            .foregroundStyle(DSColor.textSecondary)
        ForEach(Array(model.scenes.enumerated()), id: \.element.id) { index, scene in
            SceneRow(model: model, scene: scene, position: index + 1)
                .draggable(scene.id.uuidString)
                .dropDestination(for: String.self) { ids, _ in
                    guard let raw = ids.first, let id = UUID(uuidString: raw),
                          let from = model.scenes.firstIndex(where: { $0.id == id }) else { return false }
                    model.move(fromOffsets: IndexSet(integer: from), toOffset: index > from ? index + 1 : index)
                    return true
                }
        }
    }

    static func seconds(_ milliseconds: Int) -> String {
        (Double(milliseconds) / 1000).formatted(.number.precision(.fractionLength(1))) + " s"
    }
}

struct SceneRow: View {
    let model: VideoEditorModel
    let scene: VideoEditorModel.Scene
    let position: Int

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: Spacing.small) {
                HStack(spacing: Spacing.small) {
                    SceneThumbnail(url: scene.photo.fileURL)
                    VStack(alignment: .leading) {
                        Text(videoString("Cena \(position)")).font(DSFont.headline)
                        Text(ScriptStep.seconds(scene.durationMs)).font(DSFont.caption).foregroundStyle(DSColor.textSecondary)
                    }
                    Spacer(minLength: 0)
                    Menu {
                        Button { model.duplicate(scene.id) } label: { Label { Text(videoString("Duplicar")) } icon: { Image(systemName: "plus.square.on.square") } }
                        Button(role: .destructive) { model.remove(scene.id) } label: { Label { Text(videoString("Remover")) } icon: { Image(systemName: "trash") } }
                    } label: {
                        Image(systemName: "ellipsis.circle").font(.title2).frame(width: TouchTarget.minimum, height: TouchTarget.minimum)
                    }
                    .accessibilityLabel(Text(videoString("Opções da cena \(position)")))
                }
                TextField(text: Binding(get: { scene.caption }, set: { model.setCaption(scene.id, $0) }),
                          prompt: Text(videoString("Nome do cômodo"))) {
                    Text(videoString("Legenda"))
                }
                .textFieldStyle(.roundedBorder)
                .frame(minHeight: TouchTarget.minimum)
                Stepper(
                    value: Binding(get: { scene.durationMs }, set: { model.setDuration(scene.id, milliseconds: $0) }),
                    in: VideoEditorModel.durationRangeMs, step: VideoEditorModel.durationStepMs
                ) {
                    Text(videoString("Duração"))
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(videoString("Cena \(position): \(scene.caption)")))
        .accessibilityAction(named: Text(videoString("Mover para cima"))) { model.moveUp(scene.id) }
        .accessibilityAction(named: Text(videoString("Mover para baixo"))) { model.moveDown(scene.id) }
    }
}

struct SceneThumbnail: View {
    let url: URL
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image { Image(uiImage: image).resizable().scaledToFill() } else { DSColor.border }
        }
        .frame(width: 64, height: 64)
        .clipShape(RoundedRectangle(cornerRadius: Radius.small))
        .accessibilityHidden(true)
        .task(id: url) {
            image = await Task.detached { UIImage(contentsOfFile: url.path)?.preparingThumbnail(of: CGSize(width: 128, height: 128)) }.value
        }
    }
}

// MARK: - Step 3

struct CustomizeStep: View {
    let model: VideoEditorModel

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: Spacing.medium) {
                TextFieldRow(videoString("Texto de abertura"),
                             text: Binding(get: { model.openingText }, set: { model.setOpeningText($0) }),
                             prompt: videoString("Ex.: Casa de praia em Ubatuba"))
                TextFieldRow(videoString("Texto de encerramento"),
                             text: Binding(get: { model.closingText }, set: { model.setClosingText($0) }),
                             prompt: videoString("Ex.: Reserve pelo link"))
                Text(videoString("Até \(VideoEditorModel.textLimit) caracteres."))
                    .font(DSFont.caption).foregroundStyle(DSColor.textSecondary)
            }
        }
        Card {
            VStack(alignment: .leading, spacing: Spacing.small) {
                Text(videoString("Formato")).font(DSFont.headline)
                ForEach(model.supportedFormats, id: \.self) { format in
                    Toggle(isOn: Binding(get: { model.formats.contains(format) }, set: { _ in model.toggleFormat(format) })) {
                        Text(format.label)
                    }
                }
            }
        }
        Card {
            VStack(alignment: .leading, spacing: Spacing.xSmall) {
                Text(videoString("Música")).font(DSFont.headline)
                Label { Text(videoString("Sem música")) } icon: { Image(systemName: "speaker.slash") }
                Text(videoString("A biblioteca de músicas licenciadas estará disponível em breve."))
                    .font(DSFont.caption).foregroundStyle(DSColor.textSecondary)
            }
        }
    }
}

// MARK: - Step 4

struct ExportStep: View {
    let model: VideoEditorModel
    @State private var player: AVPlayer?
    @State private var savedMessage: LocalizedStringResource?

    var body: some View {
        if model.shouldWarnAboutPower {
            ErrorBanner(videoString("Bateria fraca: conecte o carregador para gerar o vídeo sem interrupções."))
        }
        if model.isPausedForHeat {
            ErrorBanner(videoString("O aparelho esquentou. O vídeo continua assim que ele esfriar."))
        }

        Group {
            if let player {
                VideoPlayer(player: player)
                    .aspectRatio(model.orderedFormats.first == .horizontal ? 16 / 9 : 9 / 16, contentMode: .fit)
                    .frame(maxHeight: 420)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.medium))
            } else if model.isRenderingPreview {
                HStack { ProgressView(); Text(videoString("Preparando a prévia…")) }
            } else {
                SecondaryButton(videoString("Ver prévia"), systemImage: "play.circle") { model.renderPreview() }
                    .disabled(!model.canExport)
            }
        }
        .onChange(of: model.previewURL) {
            player = model.previewURL.map { AVPlayer(url: $0) }
            player?.play()
        }

        switch model.exportState {
        case .idle:
            PrimaryButton(videoString("Gerar vídeo"), systemImage: "wand.and.stars") {
                player?.pause()
                model.export()
            }
            .disabled(!model.canExport)
        case .rendering(let progress, let format, let remaining):
            Card {
                HStack(spacing: Spacing.medium) {
                    ProgressRing(progress: progress).frame(width: 64, height: 64)
                    VStack(alignment: .leading) {
                        Text(videoString("Gerando \(format.label)…")).font(DSFont.headline)
                        if let remaining {
                            Text(videoString("Cerca de \(remaining) s restantes")).font(DSFont.caption).foregroundStyle(DSColor.textSecondary)
                        }
                    }
                }
            }
            SecondaryButton(videoString("Cancelar")) { model.cancelRendering() }
        case .finished(let videos):
            ForEach(videos, id: \.fileURL) { video in
                Card {
                    VStack(alignment: .leading, spacing: Spacing.small) {
                        Label { Text(videoString("Vídeo \(video.aspect.label) pronto")) } icon: { Image(systemName: "checkmark.seal.fill") }
                            .font(DSFont.headline).foregroundStyle(DSColor.success)
                        ShareLink(item: video.fileURL) {
                            Label { Text(videoString("Compartilhar")) } icon: { Image(systemName: "square.and.arrow.up") }
                                .frame(maxWidth: .infinity, minHeight: TouchTarget.minimum)
                        }
                        .buttonStyle(.borderedProminent)
                        SecondaryButton(videoString("Salvar na galeria"), systemImage: "photo.on.rectangle") {
                            Task { savedMessage = await PhotoLibrarySaver.save(video.fileURL) }
                        }
                    }
                }
            }
            if let savedMessage { Text(savedMessage).font(DSFont.callout).foregroundStyle(DSColor.textSecondary) }
        case .failed(let error):
            ErrorBanner(error.message) { model.export() }
        }
    }
}

/// Saves to the camera roll only when the user asks; requests add-only access at that moment.
enum PhotoLibrarySaver {
    static func save(_ url: URL) async -> LocalizedStringResource {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            return videoString("Sem permissão para salvar. Ative em Ajustes > CasaReel > Fotos.")
        }
        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetCreationRequest.creationRequestForAssetFromVideo(atFileURL: url)
            }
            return videoString("Vídeo salvo na galeria.")
        } catch {
            return videoString("Não foi possível salvar o vídeo.")
        }
    }
}

// MARK: - Labels

extension VideoEditorModel.Step {
    var title: LocalizedStringResource {
        switch self {
        case .template: videoString("Escolha o estilo")
        case .script: videoString("Roteiro")
        case .customize: videoString("Personalize")
        case .export: videoString("Prévia e exportação")
        }
    }
}

extension VideoTemplateInfo {
    var displayName: LocalizedStringResource {
        switch slug.rawValue {
        case "classic-clean": videoString("Clássico")
        case "cinematic-soft": videoString("Cinematográfico")
        case "dynamic-social": videoString("Dinâmico para redes")
        case "walk-tour": videoString("Walk 3D")
        default: LocalizedStringResource(stringLiteral: slug.rawValue)
        }
    }

    var summary: LocalizedStringResource {
        switch slug.rawValue {
        case "classic-clean": videoString("Zoom suave e transições em fusão.")
        case "cinematic-soft": videoString("Movimentos lentos com passagem pelo preto.")
        case "dynamic-social": videoString("Cortes rápidos, ideal para Reels e TikTok.")
        case "walk-tour": videoString("A câmera entra e anda pelos cômodos, com profundidade 3D.")
        default: videoString("Template personalizado.")
        }
    }
}

extension VideoAspect {
    var label: LocalizedStringResource {
        switch self {
        case .vertical: videoString("Vertical 9:16")
        case .horizontal: videoString("Horizontal 16:9")
        }
    }
}

extension RenderError {
    var message: LocalizedStringResource {
        switch self {
        case .insufficientStorage: videoString("Espaço insuficiente no aparelho. Libere espaço e tente de novo.")
        case .overheated: videoString("O aparelho esquentou demais. Espere esfriar e tente de novo.")
        case .unreadablePhoto: videoString("Uma das fotos não pôde ser lida. Volte e escolha as fotos novamente.")
        case .unsupportedAspect: videoString("Este estilo não oferece o formato escolhido.")
        default: videoString("Não foi possível gerar o vídeo. Tente de novo.")
        }
    }
}

func videoString(_ key: String.LocalizationValue) -> LocalizedStringResource {
    LocalizedStringResource(key, bundle: .atURL(Bundle.module.bundleURL))
}
