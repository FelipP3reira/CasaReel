import ARKit
import DesignSystem
import RealityKit
import SwiftUI
import Walk3DKit

/// Full-screen camera while the host walks. Kept out of the app switcher snapshot: it shows the inside of the home.
struct CaptureView: View {
    let model: Walk3DModel

    var body: some View {
        ZStack(alignment: .bottom) {
            CameraPreview(session: model.previewSession)
                .ignoresSafeArea()
                .accessibilityHidden(true)
            if case .capturing(let status) = model.phase {
                panel(status)
            }
        }
        .background(Color.black)
        .screenPrivacy()
    }

    private func panel(_ status: SceneCaptureStatus) -> some View {
        VStack(alignment: .leading, spacing: Spacing.medium) {
            Label { Text(Self.hint(for: status)) } icon: { Image(systemName: Self.symbol(for: status)) }
                .font(DSFont.callout)
            ProgressView(value: status.fraction) {
                Text(status.canFinish ? walkString("Pronto para gerar") : walkString("Gravando…"))
                    .font(DSFont.caption)
            }
            .accessibilityValue(Text(walkString("\(status.keyframes) de \(SceneCaptureStatus.maxKeyframes) quadros")))
            HStack(spacing: Spacing.medium) {
                SecondaryButton(walkString("Cancelar"), systemImage: "xmark") { model.cancelCapture() }
                PrimaryButton(walkString("Concluir"), systemImage: "checkmark") { model.finishCapture() }
                    .disabled(!status.canFinish)
            }
        }
        .padding(Spacing.medium)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Radius.medium))
        .padding(Spacing.medium)
    }

    static func hint(for status: SceneCaptureStatus) -> LocalizedStringResource {
        switch status.tracking {
        case .unavailable: walkString("Aponte a câmera para o cômodo e comece a andar devagar.")
        case .limited: walkString("Mais devagar e com mais luz: a câmera está perdendo a referência.")
        case .normal where status.canFinish: walkString("Já dá para gerar. Continue andando para cobrir mais da casa, ou toque em Concluir.")
        case .normal: walkString("Ande devagar, com a câmera olhando para o meio do cômodo.")
        }
    }

    static func symbol(for status: SceneCaptureStatus) -> String {
        switch status.tracking {
        case .unavailable: "camera.viewfinder"
        case .limited: "exclamationmark.triangle.fill"
        case .normal: status.canFinish ? "checkmark.circle.fill" : "figure.walk"
        }
    }
}

/// The ARKit camera feed. The session is configured and run by `ARSceneCapture`, never by the view.
private struct CameraPreview: UIViewRepresentable {
    let session: ARSession

    func makeUIView(context: Context) -> ARView {
        let view = ARView(frame: .zero, cameraMode: .ar, automaticallyConfigureSession: false)
        view.session = session
        view.renderOptions = [.disableMotionBlur, .disableDepthOfField, .disablePersonOcclusion, .disableGroundingShadows, .disableHDR]
        return view
    }

    func updateUIView(_ view: ARView, context: Context) {}
}
