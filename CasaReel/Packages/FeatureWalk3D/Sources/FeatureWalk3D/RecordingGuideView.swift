import DesignSystem
import SwiftUI

/// "Como gravar": a short, swipeable tutorial shown before picking media.
/// The 3D guide matters most: a bad recording only shows up after hours of processing on the Mac.
public struct RecordingGuideView: View {
    public enum Kind: Sendable {
        /// Videos for the real 3D walk (COLMAP + Brush).
        case video3D
        /// Photos for the 2.5D "Walk 3D" template.
        case photos
    }

    let kind: Kind
    let onDone: () -> Void
    @State private var page = 0

    public init(kind: Kind, onDone: @escaping () -> Void) {
        self.kind = kind
        self.onDone = onDone
    }

    public var body: some View {
        let pages = GuideContent.pages(for: kind)
        VStack(spacing: 0) {
            TabView(selection: $page) {
                ForEach(pages.indices, id: \.self) { index in
                    GuidePageView(page: pages[index]).tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))

            HStack(spacing: Spacing.medium) {
                if page < pages.count - 1 {
                    SecondaryButton(walkString("Pular")) { onDone() }
                    PrimaryButton(walkString("Próximo"), systemImage: "chevron.right") {
                        withAnimation { page += 1 }
                    }
                } else {
                    PrimaryButton(walkString("Entendi, vamos lá"), systemImage: "checkmark") { onDone() }
                }
            }
            .padding(Spacing.medium)
        }
        .background(DSColor.background)
    }
}

// MARK: - Content

struct GuideTip: Equatable {
    enum Kind: Equatable {
        case doThis
        case avoid
    }

    let kind: Kind
    let text: LocalizedStringResource
    let symbol: String
}

struct GuidePage: Equatable {
    enum Illustration: Equatable {
        case symbol(String)
        /// Animated floor plan with the walking route through two rooms.
        case route
    }

    let illustration: Illustration
    let title: LocalizedStringResource
    let subtitle: LocalizedStringResource?
    let tips: [GuideTip]
}

enum GuideContent {
    static func pages(for kind: RecordingGuideView.Kind) -> [GuidePage] {
        switch kind {
        case .video3D: video3D
        case .photos: photos
        }
    }

    static let video3D: [GuidePage] = [
        GuidePage(
            illustration: .symbol("lightbulb.max"),
            title: walkString("Antes de gravar, prepare a casa"),
            subtitle: walkString("O 3D só fica bom com luz e com tudo parado."),
            tips: [
                GuideTip(kind: .doThis, text: walkString("Acenda todas as luzes e abra as cortinas."), symbol: "lightbulb"),
                GuideTip(kind: .doThis, text: walkString("Arrume o que vai aparecer: o vídeo é o anúncio."), symbol: "sparkles"),
                GuideTip(kind: .avoid, text: walkString("Tire pessoas e animais do caminho."), symbol: "person.2.slash"),
                GuideTip(kind: .avoid, text: walkString("Desligue TV e ventiladores: o que se mexe confunde o 3D."), symbol: "fan"),
                GuideTip(kind: .avoid, text: walkString("Guarde documentos e fotos de família."), symbol: "doc.text"),
            ]
        ),
        GuidePage(
            illustration: .symbol("camera"),
            title: walkString("Configure a câmera"),
            subtitle: walkString("Use o app Câmera do iPhone, no modo Vídeo."),
            tips: [
                GuideTip(kind: .doThis, text: walkString("Lente 1× e sem zoom durante a gravação."), symbol: "camera.aperture"),
                GuideTip(kind: .doThis, text: walkString("Celular deitado (na horizontal): pega mais do cômodo."), symbol: "iphone.landscape"),
                GuideTip(kind: .doThis, text: walkString("Limpe a lente antes de começar."), symbol: "hand.raised"),
                GuideTip(kind: .avoid, text: walkString("Não use os modos Cinematográfico, Ação, Câmera lenta ou Timelapse."), symbol: "film"),
            ]
        ),
        GuidePage(
            illustration: .symbol("iphone.landscape"),
            title: walkString("Segure firme, na altura do peito"),
            subtitle: nil,
            tips: [
                GuideTip(kind: .doThis, text: walkString("Use as duas mãos, com os cotovelos junto ao corpo."), symbol: "hands.clap"),
                GuideTip(kind: .doThis, text: walkString("Câmera reta: nem para o chão, nem para o teto."), symbol: "level"),
                GuideTip(kind: .avoid, text: walkString("Não gire o celular de deitado para em pé no meio do vídeo."), symbol: "rotate.right"),
            ]
        ),
        GuidePage(
            illustration: .route,
            title: walkString("Ande devagar, sempre se movendo"),
            subtitle: walkString("É o passo mais importante: o 3D nasce da diferença entre um ponto de vista e outro."),
            tips: [
                GuideTip(kind: .doThis, text: walkString("Um passo por segundo, como num passeio calmo."), symbol: "tortoise"),
                GuideTip(kind: .doThis, text: walkString("Dê uma volta pelo cômodo, perto das paredes, com a câmera olhando para o meio."), symbol: "arrow.trianglehead.clockwise"),
                GuideTip(kind: .doThis, text: walkString("Vire devagar: uns 4 segundos para fazer uma curva."), symbol: "arrow.turn.up.right"),
                GuideTip(kind: .avoid, text: walkString("Não gire parado no lugar: sem andar, não há 3D."), symbol: "arrow.clockwise"),
            ]
        ),
        GuidePage(
            illustration: .symbol("door.left.hand.open"),
            title: walkString("Passe de um cômodo para o outro sem parar"),
            subtitle: walkString("É a passagem pelas portas que liga os cômodos no 3D."),
            tips: [
                GuideTip(kind: .doThis, text: walkString("Continue gravando ao atravessar a porta, de frente e devagar."), symbol: "door.left.hand.open"),
                GuideTip(kind: .doThis, text: walkString("De 1 a 3 minutos por vídeo. Uma casa inteira cabe em 2 ou 3 vídeos."), symbol: "timer"),
                GuideTip(kind: .doThis, text: walkString("Se parar, comece o próximo vídeo de onde o anterior terminou."), symbol: "arrow.right.to.line"),
            ]
        ),
        GuidePage(
            illustration: .symbol("exclamationmark.triangle"),
            title: walkString("O que atrapalha o 3D"),
            subtitle: nil,
            tips: [
                GuideTip(kind: .avoid, text: walkString("Espelhos e vidros grandes: o 3D \"vê\" um cômodo que não existe."), symbol: "rectangle.portrait"),
                GuideTip(kind: .avoid, text: walkString("Filmar contra janelas com sol direto."), symbol: "sun.max"),
                GuideTip(kind: .avoid, text: walkString("Chegar muito perto de paredes lisas ou cantos escuros."), symbol: "square.dashed"),
                GuideTip(kind: .avoid, text: walkString("Movimentos bruscos e vídeo tremido."), symbol: "waveform.path"),
            ]
        ),
        GuidePage(
            illustration: .symbol("checkmark.seal"),
            title: walkString("Resumo rápido"),
            subtitle: walkString("Depois, escolha os vídeos (e, se quiser, as fotos do anúncio) no passo 1."),
            tips: [
                GuideTip(kind: .doThis, text: walkString("Luzes acesas, casa arrumada, ninguém no caminho."), symbol: "lightbulb"),
                GuideTip(kind: .doThis, text: walkString("Modo Vídeo, lente 1×, celular deitado na altura do peito."), symbol: "camera"),
                GuideTip(kind: .doThis, text: walkString("Ande devagar, vire devagar, sem parar nas portas."), symbol: "figure.walk"),
                GuideTip(kind: .doThis, text: walkString("Fotos do anúncio ajudam nos detalhes, mas o vídeo é essencial."), symbol: "photo.on.rectangle"),
            ]
        ),
    ]

    static let photos: [GuidePage] = [
        GuidePage(
            illustration: .symbol("photo"),
            title: walkString("Fotos para o efeito Walk"),
            subtitle: walkString("O vídeo \"entra\" em cada foto. Estas dicas deixam o movimento mais natural."),
            tips: [
                GuideTip(kind: .doThis, text: walkString("Fotografe da porta ou de um canto, mostrando o cômodo inteiro."), symbol: "door.left.hand.open"),
                GuideTip(kind: .doThis, text: walkString("Celular deitado e reto: linhas das paredes em pé, sem inclinar."), symbol: "iphone.landscape"),
                GuideTip(kind: .doThis, text: walkString("Deixe o meio da foto livre: é por ali que a câmera \"anda\"."), symbol: "arrow.up.forward"),
                GuideTip(kind: .doThis, text: walkString("Luzes acesas e cortinas abertas, sem filmar contra o sol."), symbol: "lightbulb"),
                GuideTip(kind: .avoid, text: walkString("Móveis colados na câmera e fotos muito fechadas (zoom)."), symbol: "plus.magnifyingglass"),
            ]
        ),
    ]
}

// MARK: - Page

private struct GuidePageView: View {
    let page: GuidePage
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.medium) {
                illustration
                    .frame(maxWidth: .infinity)
                    .frame(height: 180)
                    .background(RoundedRectangle(cornerRadius: Radius.large).fill(DSColor.surface))
                    .accessibilityHidden(true)
                Text(page.title)
                    .font(DSFont.title)
                    .foregroundStyle(DSColor.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                if let subtitle = page.subtitle {
                    Text(subtitle).font(DSFont.callout).foregroundStyle(DSColor.textSecondary)
                }
                VStack(alignment: .leading, spacing: Spacing.small) {
                    ForEach(page.tips.indices, id: \.self) { index in
                        TipRow(tip: page.tips[index])
                    }
                }
            }
            .padding(Spacing.medium)
            .padding(.bottom, Spacing.xLarge)
        }
    }

    @ViewBuilder
    private var illustration: some View {
        switch page.illustration {
        case .symbol(let name):
            Image(systemName: name)
                .font(.system(size: 72, weight: .regular))
                .foregroundStyle(DSColor.accent)
                .symbolEffect(.pulse, options: .repeating, isActive: !reduceMotion)
        case .route:
            RouteIllustration()
                .padding(Spacing.medium)
        }
    }
}

private struct TipRow: View {
    let tip: GuideTip

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.small) {
            Image(systemName: tip.kind == .doThis ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(tip.kind == .doThis ? DSColor.success : DSColor.danger)
                .font(DSFont.headline)
            Image(systemName: tip.symbol)
                .foregroundStyle(DSColor.textSecondary)
                .frame(width: 24)
            Text(tip.text)
                .font(DSFont.body)
                .foregroundStyle(DSColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(tip.kind == .doThis ? walkString("Faça: \(String(localized: tip.text))") : walkString("Evite: \(String(localized: tip.text))")))
    }
}

/// Two rooms seen from above, joined by a door, with the recommended route drawn as it is walked:
/// a loop along the walls of the first room, through the door, and a loop in the second.
struct RouteIllustration: View {
    nonisolated static let loopSeconds = 6.0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // Driven by the clock, so the walker follows the route instead of cutting straight across.
        TimelineView(.animation(paused: reduceMotion)) { context in
            let progress = reduceMotion ? 1 : Self.progress(at: context.date)
            GeometryReader { geometry in
                ZStack {
                    FloorPlan()
                        .stroke(DSColor.textSecondary, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    Route()
                        .trim(from: 0, to: progress)
                        .stroke(DSColor.accent, style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [6, 6]))
                    Image(systemName: "figure.walk")
                        .font(DSFont.headline)
                        .foregroundStyle(DSColor.accent)
                        .position(Route.point(at: progress, in: CGRect(origin: .zero, size: geometry.size)))
                }
            }
        }
    }

    nonisolated static func progress(at date: Date) -> CGFloat {
        CGFloat(date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: loopSeconds) / loopSeconds)
    }
}

/// Outline of two side-by-side rooms with a door gap in the shared wall.
struct FloorPlan: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let mid = rect.midX, doorTop = rect.minY + rect.height * 0.4, doorBottom = rect.minY + rect.height * 0.6
        path.addRect(rect)
        path.move(to: CGPoint(x: mid, y: rect.minY))
        path.addLine(to: CGPoint(x: mid, y: doorTop))
        path.move(to: CGPoint(x: mid, y: doorBottom))
        path.addLine(to: CGPoint(x: mid, y: rect.maxY))
        return path
    }
}

/// The walking route: around the left room, through the door, around the right room.
struct Route: Shape {
    /// Normalized waypoints (0–1 in each axis).
    static let waypoints: [CGPoint] = [
        CGPoint(x: 0.12, y: 0.5), CGPoint(x: 0.12, y: 0.18), CGPoint(x: 0.4, y: 0.18), CGPoint(x: 0.4, y: 0.82),
        CGPoint(x: 0.12, y: 0.82), CGPoint(x: 0.12, y: 0.5), CGPoint(x: 0.5, y: 0.5), CGPoint(x: 0.6, y: 0.5),
        CGPoint(x: 0.6, y: 0.18), CGPoint(x: 0.88, y: 0.18), CGPoint(x: 0.88, y: 0.82), CGPoint(x: 0.6, y: 0.82),
    ]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addLines(Self.waypoints.map { Self.scale($0, to: rect) })
        return path
    }

    static func scale(_ point: CGPoint, to rect: CGRect) -> CGPoint {
        CGPoint(x: rect.minX + point.x * rect.width, y: rect.minY + point.y * rect.height)
    }

    /// The point a fraction of the way along the route (by length), for the walking figure.
    static func point(at fraction: CGFloat, in rect: CGRect) -> CGPoint {
        let points = waypoints.map { scale($0, to: rect) }
        let lengths = zip(points, points.dropFirst()).map { hypot($1.x - $0.x, $1.y - $0.y) }
        var remaining = min(max(fraction, 0), 1) * lengths.reduce(0, +)
        for (index, length) in lengths.enumerated() {
            if remaining <= length, length > 0 {
                let t = remaining / length
                return CGPoint(x: points[index].x + (points[index + 1].x - points[index].x) * t,
                               y: points[index].y + (points[index + 1].y - points[index].y) * t)
            }
            remaining -= length
        }
        return points.last ?? .zero
    }
}
