import DesignSystem
import Domain
import ImageIO
import PhotosUI
import SwiftUI

/// Pick 5–40 photos, see each one's preparation status, reorder by dragging and remove.
public struct PhotoSelectionView: View {
    @Bindable private var model: PhotoSelectionModel
    private let onContinue: ([PreparedPhoto]) -> Void
    @State private var pickerItems: [PhotosPickerItem] = []

    public init(model: PhotoSelectionModel, onContinue: @escaping ([PreparedPhoto]) -> Void) {
        self.model = model
        self.onContinue = onContinue
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.medium) {
                Label {
                    Text("Removemos localização e metadados das fotos antes de enviar.", bundle: .module)
                } icon: {
                    Image(systemName: "lock.shield")
                }
                .font(DSFont.callout)
                .foregroundStyle(DSColor.textSecondary)

                PhotosPicker(
                    selection: $pickerItems,
                    maxSelectionCount: max(model.remainingSlots, 1),
                    selectionBehavior: .ordered,
                    matching: .images,
                    preferredItemEncoding: .current
                ) {
                    Label { Text("Adicionar fotos", bundle: .module) } icon: { Image(systemName: "photo.badge.plus") }
                        .font(DSFont.button)
                        .frame(maxWidth: .infinity, minHeight: TouchTarget.minimum)
                }
                .buttonStyle(.bordered)
                .disabled(model.remainingSlots == 0)
                .onChange(of: pickerItems) {
                    guard !pickerItems.isEmpty else { return }
                    model.add(pickerItems.map(PickedPhotoSource.init(item:)))
                    pickerItems = []
                }

                Text(counterText)
                    .font(DSFont.headline)
                    .foregroundStyle(DSColor.textPrimary)
                    .accessibilityAddTraits(.updatesFrequently)

                if model.rejectedCount > 0 {
                    ErrorBanner(rejectedMessage, retry: model.removeRejected)
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: Spacing.small)], spacing: Spacing.small) {
                    ForEach(model.items) { item in
                        PhotoCell(item: item) { model.remove(item.id) }
                            .draggable(item.id.uuidString)
                            .dropDestination(for: String.self) { identifiers, _ in
                                guard let raw = identifiers.first, let source = UUID(uuidString: raw) else { return false }
                                model.move(source, to: item.id)
                                return true
                            }
                    }
                }

                if model.hasAnalyses {
                    SecondaryButton(featureString("Aplicar ordem sugerida"), systemImage: "list.number") {
                        model.applySuggestedOrder()
                    }
                    Text("Fachada, sala, cozinha, quartos, banheiros e área externa. Você ainda pode arrastar para ajustar.", bundle: .module)
                        .font(DSFont.caption)
                        .foregroundStyle(DSColor.textSecondary)
                }

                if !model.suggestions.isEmpty {
                    Card {
                        VStack(alignment: .leading, spacing: Spacing.small) {
                            Text("Sugestões", bundle: .module)
                                .font(DSFont.headline)
                                .accessibilityAddTraits(.isHeader)
                            ForEach(model.suggestions, id: \.position) { suggestion in
                                ForEach(suggestion.warnings, id: \.self) { warning in
                                    Label {
                                        Text(featureString("Foto \(suggestion.position): \(warning.advice)"))
                                    } icon: {
                                        Image(systemName: "lightbulb")
                                    }
                                    .font(DSFont.callout)
                                    .foregroundStyle(DSColor.textPrimary)
                                }
                            }
                        }
                    }
                }

                Toggle(isOn: $model.blurFaces) {
                    VStack(alignment: .leading) {
                        Text("Borrar rostos", bundle: .module)
                        Text(model.hasFaces ? featureString("Rostos encontrados nas fotos serão desfocados.") : featureString("Nenhum rosto encontrado até agora."))
                            .font(DSFont.caption)
                            .foregroundStyle(DSColor.textSecondary)
                    }
                }

                PrimaryButton(continueTitle) {
                    Task { onContinue(await model.finalizedPhotos()) }
                }
                .disabled(!model.canContinue)
            }
            .padding(Spacing.medium)
        }
        .background(DSColor.background)
    }

    private var counterText: LocalizedStringResource {
        featureString("\(model.readyPhotos.count) de \(PhotoLimits.maximumCount) fotos (mínimo \(PhotoLimits.minimumCount))")
    }

    private var rejectedMessage: LocalizedStringResource {
        featureString("\(model.rejectedCount) foto(s) não puderam ser usadas. Toque para remover.")
    }

    private var continueTitle: LocalizedStringResource {
        model.isPreparing ? featureString("Preparando fotos…") : featureString("Continuar")
    }
}

/// One thumbnail with its status, duplicate warning and remove button.
struct PhotoCell: View {
    let item: PhotoSelectionModel.Item
    let onRemove: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            content
                .frame(minWidth: 0, maxWidth: .infinity)
                .aspectRatio(1, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: Radius.small))

            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .black.opacity(0.6))
                    .font(.title3)
                    .frame(width: TouchTarget.minimum, height: TouchTarget.minimum)
            }
            .accessibilityLabel(Text("Remover foto", bundle: .module))
        }
        .overlay(alignment: .bottomLeading) {
            VStack(alignment: .leading, spacing: Spacing.xSmall) {
                if let duplicate = item.duplicate {
                    Tag(duplicate == .exact ? featureString("Repetida") : featureString("Parecida"), style: .warning)
                        .background(Capsule().fill(DSColor.surface))
                }
                if let analysis = item.analysis {
                    Tag(analysis.room.label, style: analysis.warnings.isEmpty ? .neutral : .warning)
                        .background(Capsule().fill(DSColor.surface))
                }
            }
            .padding(Spacing.xSmall)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    @ViewBuilder private var content: some View {
        switch item.state {
        case .preparing:
            ZStack {
                SkeletonView(height: 104)
                ProgressView()
            }
        case .ready(let photo):
            ThumbnailView(url: photo.fileURL)
        case .rejected(let reason):
            VStack(spacing: Spacing.xSmall) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(DSColor.danger)
                    .accessibilityHidden(true)
                Text(reason.message)
                    .font(DSFont.caption)
                    .foregroundStyle(DSColor.textPrimary)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.8)
            }
            .padding(Spacing.small)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(DSColor.danger.opacity(0.12))
        }
    }

    private var accessibilityText: Text {
        switch item.state {
        case .preparing: Text("Foto sendo preparada", bundle: .module)
        case .ready:
            if let analysis = item.analysis {
                Text(featureString("Foto pronta: \(analysis.room.label), \(analysis.warnings.isEmpty ? featureString("boa qualidade") : analysis.warnings[0].title)"))
            } else {
                item.duplicate == nil ? Text("Foto pronta", bundle: .module) : Text("Foto pronta, possível repetição", bundle: .module)
            }
        case .rejected(let reason): Text(reason.message)
        }
    }
}

/// Downsampled thumbnail decoded off the main thread.
struct ThumbnailView: View {
    let url: URL
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                SkeletonView(height: 104)
            }
        }
        .task(id: url) {
            image = await Self.load(url)
        }
    }

    nonisolated static func load(_ url: URL) async -> UIImage? {
        await Task.detached(priority: .userInitiated) {
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 320,
            ]
            guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
                  let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
            else { return nil }
            return UIImage(cgImage: thumbnail)
        }.value
    }
}

extension PhotoRejection {
    var message: LocalizedStringResource {
        switch self {
        case .unsupportedType: featureString("Formato não suportado. Use JPEG, HEIC ou PNG.")
        case .fileTooLarge: featureString("Arquivo maior que 25 MB.")
        case .tooSmall: featureString("Resolução baixa: mínimo de 1280 px no lado maior.")
        case .tooManyPixels: featureString("Imagem grande demais (mais de 50 megapixels).")
        case .unreadable: featureString("Não foi possível ler esta foto.")
        }
    }
}

extension RoomType {
    var label: LocalizedStringResource {
        switch self {
        case .facade: featureString("Fachada")
        case .livingRoom: featureString("Sala")
        case .kitchen: featureString("Cozinha")
        case .bedroom: featureString("Quarto")
        case .bathroom: featureString("Banheiro")
        case .balcony: featureString("Varanda")
        case .pool: featureString("Piscina")
        case .other: featureString("Outro")
        }
    }
}

extension QualityWarning {
    var title: LocalizedStringResource {
        switch self {
        case .blurry: featureString("Foto desfocada")
        case .tooDark: featureString("Muito escura")
        case .tooBright: featureString("Muito clara")
        case .noisy: featureString("Com granulado")
        }
    }

    var advice: LocalizedStringResource {
        switch self {
        case .blurry: featureString("Foto desfocada. Segure o celular firme e toque na tela para focar.")
        case .tooDark: featureString("Muito escura. Acenda as luzes ou abra as janelas e tire outra foto.")
        case .tooBright: featureString("Muito clara. Evite fotografar contra a luz da janela.")
        case .noisy: featureString("Com granulado. Fotografe com mais luz.")
        }
    }
}

func featureString(_ key: String.LocalizationValue) -> LocalizedStringResource {
    LocalizedStringResource(key, bundle: .atURL(Bundle.module.bundleURL))
}
