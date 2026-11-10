import AVKit
import DesignSystem
import Photos
import SwiftUI
import Walk3DKit

/// Walk 3D: record the rooms, and the phone builds the 3D and the walk video by itself.
public struct Walk3DView: View {
    let model: Walk3DModel
    @State private var isShowingGuide = false
    @Environment(\.scenePhase) private var scenePhase
    /// Not sensitive: only whether the tutorial was already shown on this device.
    @AppStorage("walk3d.recordingGuideSeen") private var guideSeen = false

    public init(model: Walk3DModel) {
        self.model = model
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.large) {
                Text(walkString("Grave andando pelos cômodos e o iPhone monta o 3D e o vídeo sozinho, sem enviar nada para fora do aparelho."))
                    .font(DSFont.body)
                    .foregroundStyle(DSColor.textSecondary)
                recordStep
                processStep
                if case .finished(let video) = model.phase {
                    FinishedVideo(video: video)
                }
                if model.watermark {
                    Text(walkString("No plano grátis o vídeo sai com a marca d'água CasaReel."))
                        .font(DSFont.caption)
                        .foregroundStyle(DSColor.textSecondary)
                }
            }
            .padding(Spacing.medium)
        }
        .background(DSColor.background)
        .fullScreenCover(isPresented: Binding(get: { model.isCapturing }, set: { if !$0 { model.cancelCapture() } })) {
            CaptureView(model: model)
        }
        .sheet(isPresented: $isShowingGuide) {
            RecordingGuideView(kind: .video3D) {
                guideSeen = true
                isShowingGuide = false
            }
            .presentationDragIndicator(.visible)
        }
        .onChange(of: scenePhase) {
            if scenePhase == .background { model.appDidLeaveForeground() }
        }
        .task {
            if !guideSeen { isShowingGuide = true }
        }
    }

    // MARK: - Step 1

    private var recordStep: some View {
        Card {
            VStack(alignment: .leading, spacing: Spacing.small) {
                StepTitle(number: 1, title: walkString("Grave a casa"))
                Text(walkString("Ande devagar pelos cômodos com o celular na altura do peito, de 1 a 3 minutos. Evite pessoas, espelhos e documentos à vista."))
                    .font(DSFont.caption)
                    .foregroundStyle(DSColor.textSecondary)
                Button { isShowingGuide = true } label: {
                    Label { Text(walkString("Como gravar (tutorial)")) } icon: { Image(systemName: "play.rectangle.on.rectangle") }
                        .frame(minHeight: TouchTarget.minimum)
                }
                if model.isSupported {
                    PrimaryButton(walkString("Gravar"), systemImage: "video.fill") { model.startCapture() }
                        .disabled(model.isWorking)
                } else {
                    ErrorBanner(Failure.unsupported.message)
                }
            }
        }
    }

    // MARK: - Steps 2 and 3

    private var processStep: some View {
        Card {
            VStack(alignment: .leading, spacing: Spacing.small) {
                StepTitle(number: 2, title: walkString("O iPhone monta o 3D e o vídeo"))
                switch model.phase {
                case .idle, .capturing:
                    Text(walkString("Começa sozinho quando você concluir a gravação. Leva alguns minutos: deixe o app aberto e a tela ligada."))
                        .font(DSFont.caption)
                        .foregroundStyle(DSColor.textSecondary)
                case .savingCapture:
                    progressRow(nil, label: walkString("Salvando a gravação…"))
                case .training(let progress, let pausedForHeat):
                    progressRow(progress, label: pausedForHeat ? Self.heatMessage : walkString("Montando o 3D da casa…"))
                case .rendering(let progress, let pausedForHeat):
                    progressRow(progress, label: pausedForHeat ? Self.heatMessage : walkString("Gerando o vídeo andando…"))
                case .finished:
                    Label { Text(walkString("Vídeo pronto.")) } icon: { Image(systemName: "checkmark.seal.fill") }
                        .font(DSFont.callout)
                        .foregroundStyle(DSColor.success)
                    SecondaryButton(walkString("Gravar de novo"), systemImage: "video") { model.startCapture() }
                case .failed(let failure):
                    ErrorBanner(failure.message, retry: model.canRetry ? { model.retry() } : nil)
                    if failure != .unsupported {
                        SecondaryButton(walkString("Gravar de novo"), systemImage: "video") { model.startCapture() }
                    }
                }
            }
        }
    }

    private static let heatMessage = walkString("O aparelho esquentou. Continua assim que esfriar.")

    private func progressRow(_ progress: Double?, label: LocalizedStringResource) -> some View {
        HStack(spacing: Spacing.medium) {
            if let progress {
                ProgressRing(progress: progress).frame(width: 48, height: 48)
            } else {
                ProgressView()
            }
            VStack(alignment: .leading) {
                Text(label).font(DSFont.callout)
                Text(walkString("Deixe o app aberto e a tela ligada."))
                    .font(DSFont.caption)
                    .foregroundStyle(DSColor.textSecondary)
            }
            Spacer()
            Button(role: .cancel) { model.cancelProcessing() } label: { Text(walkString("Cancelar")) }
                .frame(minHeight: TouchTarget.minimum)
        }
    }

    typealias Failure = Walk3DModel.Failure
}

struct StepTitle: View {
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
    private nonisolated static func save(_ url: URL) async -> LocalizedStringResource {
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

// MARK: - Messages

extension Walk3DModel.Failure {
    var message: LocalizedStringResource {
        switch self {
        case .unsupported: walkString("Este aparelho não grava em 3D (o simulador também não).")
        case .cameraDenied: walkString("Sem acesso à câmera. Ative em Ajustes > CasaReel > Câmera.")
        case .captureTooShort: walkString("A gravação ficou curta demais. Ande um pouco mais pelos cômodos.")
        case .captureInterrupted: walkString("A gravação parou porque o app saiu da tela. Grave de novo.")
        case .insufficientStorage: walkString("Pouco espaço livre no iPhone.")
        case .interrupted: walkString("O app saiu da tela e o processamento parou. Toque em Tentar de novo.")
        case .overheated: walkString("O aparelho esquentou demais. Tente de novo em alguns minutos.")
        case .failed: walkString("Não foi possível gerar o vídeo.")
        }
    }
}

func walkString(_ key: String.LocalizationValue) -> LocalizedStringResource {
    LocalizedStringResource(key, bundle: .atURL(Bundle.module.bundleURL))
}
