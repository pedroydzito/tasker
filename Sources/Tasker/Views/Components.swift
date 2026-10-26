import SwiftUI

// MARK: Tema

/// Tokens de cor do Tasker (claro/escuro). Visual limpo: fundo neutro, cartões brancos, grupos cinza-claro.
enum Theme {
    static let canvas = dynamic(light: "#F5F5F7", dark: "#161618")
    static let surface = dynamic(light: "#FFFFFF", dark: "#232326")
    static let group = dynamic(light: "#EDEDF0", dark: "#1D1D20")
    static let stroke = dynamic(light: "#E4E4E8", dark: "#303035")
    static let subtle = dynamic(light: "#86868F", dark: "#8E8E97")
    static let field = dynamic(light: "#F1F1F3", dark: "#2A2A2E")
    static let eventFill = dynamic(light: "#EAF1FD", dark: "#1F2737")

    static func dynamic(light: String, dark: String) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? NSColor(hex: dark) : NSColor(hex: light)
        })
    }
}

enum Palette {
    static let lists = ["#8E5BE8", "#F2683C", "#2F80ED", "#27AE60", "#EB5757", "#E2A93B", "#2DB7C7", "#D45BB0", "#5E6AD2", "#8A8F98"]
}

extension NSColor {
    convenience init(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        var value: UInt64 = 0
        Scanner(string: s).scanHexInt64(&value)
        self.init(srgbRed: CGFloat((value >> 16) & 0xFF) / 255, green: CGFloat((value >> 8) & 0xFF) / 255,
                  blue: CGFloat(value & 0xFF) / 255, alpha: 1)
    }
}

extension Color {
    init(hex: String) {
        self.init(nsColor: NSColor(hex: hex))
    }

    var hexString: String {
        let c = NSColor(self).usingColorSpace(.sRGB) ?? .gray
        return String(format: "#%02X%02X%02X", Int(round(c.redComponent * 255)),
                      Int(round(c.greenComponent * 255)), Int(round(c.blueComponent * 255)))
    }

    /// Versão legível da cor para texto sobre o fundo claro da própria cor (como as pílulas do Dribbble).
    var ink: Color {
        let base = NSColor(self).usingColorSpace(.sRGB) ?? .gray
        return Color(nsColor: NSColor(name: nil) { appearance in
            let dark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return base.blended(withFraction: dark ? 0.35 : 0.4, of: dark ? .white : .black) ?? base
        })
    }
}

// MARK: Listas

/// Ícone da lista: foto, emoji ou bolinha da cor.
struct ListIconView: View {
    @Environment(TaskStore.self) private var store
    let listID: String
    var size: CGFloat = 16

    var body: some View {
        if let photo = store.photo(forList: listID) {
            Image(nsImage: photo)
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
                .clipShape(Circle())
        } else if let emoji = store.emoji(forList: listID) {
            Text(emoji)
                .font(.system(size: size * 0.82))
                .frame(width: size, height: size)
        } else {
            Circle()
                .fill(store.color(forList: listID))
                .frame(width: size * 0.55, height: size * 0.55)
                .frame(width: size, height: size)
        }
    }
}

/// Pílula da lista: fundo na cor da lista, ícone personalizável e só o nome.
struct ListChip: View {
    @Environment(TaskStore.self) private var store
    let listID: String
    var showIcon = true

    var body: some View {
        let color = store.color(forList: listID)
        HStack(spacing: 4) {
            if showIcon, store.photo(forList: listID) != nil || store.emoji(forList: listID) != nil {
                ListIconView(listID: listID, size: 13)
            }
            Text(store.displayName(listID)).lineLimit(1)
        }
        .font(.system(size: 11.5, weight: .medium))
        .foregroundStyle(color.ink)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(color.opacity(0.16), in: Capsule())
    }
}

/// Editor de aparência da lista: emoji, foto e cor.
struct ListAppearanceEditor: View {
    @Environment(TaskStore.self) private var store
    let listID: String
    @State private var emoji = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                ListIconView(listID: listID, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(store.displayName(listID)).font(.headline)
                    Text("Aparência no Tasker").font(.caption).foregroundStyle(.secondary)
                }
            }

            HStack {
                Text("Emoji").frame(width: 50, alignment: .leading)
                TextField("🙂", text: $emoji)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 60)
                    .onChange(of: emoji) { _, value in
                        let first = value.first.map(String.init)
                        if value.count > 1 { emoji = first ?? "" }
                        store.setEmoji(first, forList: listID)
                    }
                Button("Emojis…") { NSApp.orderFrontCharacterPalette(nil) }
                    .controlSize(.small)
            }

            HStack {
                Text("Foto").frame(width: 50, alignment: .leading)
                Button("Escolher foto…", action: choosePhoto).controlSize(.small)
                if store.photo(forList: listID) != nil {
                    Button("Remover", role: .destructive) { store.removePhoto(forList: listID) }
                        .controlSize(.small)
                }
            }

            HStack {
                Text("Cor").frame(width: 50, alignment: .leading)
                ColorPicker("", selection: Binding(
                    get: { store.color(forList: listID) },
                    set: { store.setColor($0, forList: listID) }
                ), supportsOpacity: false)
                .labelsHidden()
                ListChip(listID: listID)
            }
        }
        .padding(16)
        .frame(width: 300)
        .onAppear { emoji = store.emoji(forList: listID) ?? "" }
    }

    private func choosePhoto() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.message = "Escolha uma foto para a lista \(store.displayName(listID))"
        if panel.runModal() == .OK, let url = panel.url {
            store.setPhoto(from: url, forList: listID)
        }
    }
}

// MARK: Seções e controles

/// Grupo de tarefas: contêiner cinza arredondado com título em caixa alta e contador.
struct TaskSection<Content: View>: View {
    let title: String
    let count: Int
    var tint: Color?
    var accessory: AnyView?
    @ViewBuilder var content: Content
    @State private var collapsed: Bool

    init(_ title: String, count: Int, tint: Color? = nil, startCollapsed: Bool = false,
         accessory: AnyView? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.count = count
        self.tint = tint
        self.accessory = accessory
        self.content = content()
        _collapsed = State(initialValue: startCollapsed)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Button {
                    withAnimation(.snappy(duration: 0.2)) { collapsed.toggle() }
                } label: {
                    HStack(spacing: 7) {
                        Text(title.uppercased())
                            .font(.system(size: 11.5, weight: .semibold))
                            .tracking(0.8)
                            .foregroundStyle(tint ?? Theme.subtle)
                        Text("\(count)")
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(Theme.subtle)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                        Image(systemName: "chevron.down")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(Theme.subtle.opacity(0.7))
                            .rotationEffect(.degrees(collapsed ? -90 : 0))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Spacer()
                if let accessory { accessory }
            }
            .padding(.horizontal, 6)
            .padding(.top, 2)

            if !collapsed {
                LazyVStack(spacing: 6) { content }
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(10)
        .background(Theme.group, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

/// Cabeçalho simples (usado no popover compacto).
struct SectionHeader: View {
    let title: String
    let count: Int
    var tint: Color = Theme.subtle

    var body: some View {
        HStack(spacing: 6) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.6)
            Text("\(count)")
                .font(.system(size: 11, weight: .medium))
                .opacity(0.6)
            Spacer()
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 10)
        .padding(.top, 10)
        .padding(.bottom, 2)
    }
}

/// Segmentado em formato de pílula (como "All / Remote / In Person" da referência).
struct PillPicker<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [(Value, String)]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options.indices, id: \.self) { index in
                let (value, label) = options[index]
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { selection = value }
                } label: {
                    Text(label)
                        .font(.system(size: 12.5, weight: selection == value ? .semibold : .regular))
                        .foregroundStyle(selection == value ? Color.primary : Theme.subtle)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background {
                            if selection == value {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Theme.surface)
                                    .shadow(color: .black.opacity(0.06), radius: 2, y: 1)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Theme.group, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

/// Círculo de conclusão colorido com a cor da lista.
struct CheckCircle: View {
    let color: Color
    let checked: Bool
    var size: CGFloat = 18
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle().strokeBorder(color, lineWidth: 1.6)
                Circle().fill(color).opacity(checked ? 1 : (hovering ? 0.12 : 0))
                if checked || hovering {
                    Image(systemName: "checkmark")
                        .font(.system(size: size * 0.47, weight: .heavy))
                        .foregroundStyle(checked ? Color.white : color)
                }
            }
            .frame(width: size, height: size)
            .contentShape(Circle())
        }
        .buttonStyle(CheckPressStyle())
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: checked)
        .help(checked ? "Reabrir" : "Concluir")
    }
}

/// Foto da conta Google.
struct Avatar: View {
    @Environment(GoogleAuth.self) private var auth
    var size: CGFloat = 26

    var body: some View {
        Group {
            if let image = auth.avatar {
                Image(nsImage: image).resizable().scaledToFill()
            } else {
                ZStack {
                    Circle().fill(Color.accentColor.opacity(0.18))
                    Text(String((auth.profile?.name ?? auth.profile?.email ?? "?").prefix(1)).uppercased())
                        .font(.system(size: size * 0.45, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }

    /// Imagem já recortada em círculo e no tamanho certo (rótulos de Menu ignoram .frame).
    @MainActor
    static func menuImage(_ image: NSImage?, side: CGFloat) -> NSImage {
        guard let image else {
            return NSImage(systemSymbolName: "person.crop.circle.fill", accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(pointSize: side - 4, weight: .regular)) ?? NSImage()
        }
        return NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            NSBezierPath(ovalIn: rect).addClip()
            let s = image.size
            let scale = max(side / max(s.width, 1), side / max(s.height, 1))
            let w = s.width * scale, h = s.height * scale
            image.draw(in: NSRect(x: (side - w) / 2, y: (side - h) / 2, width: w, height: h))
            return true
        }
    }
}

struct DueLabel: View {
    let day: Date
    let today: Date
    var showIcon = true

    var body: some View {
        let overdue = day < today
        let isToday = day == today
        HStack(spacing: 4) {
            if showIcon { Image(systemName: overdue ? "exclamationmark.circle" : "clock") }
            Text(DayLabel.short(day, today: today))
        }
        .foregroundStyle(overdue ? Color.red : (isToday ? Color.accentColor : Theme.subtle))
    }
}

/// Etiqueta local (só no app).
struct TagChip: View {
    let name: String
    let color: Color

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "tag").font(.system(size: 9, weight: .semibold))
            Text(name).lineLimit(1)
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(color.ink)
    }
}

/// Faixa discreta para erros de sincronização.
struct ErrorBanner: View {
    @Environment(TaskStore.self) private var store

    var body: some View {
        if let error = store.lastError {
            Banner(symbol: "exclamationmark.triangle.fill", tint: .orange, message: error) {
                Button { store.lastError = nil } label: { Image(systemName: "xmark") }
                    .buttonStyle(.plain)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

/// Aviso quando o Google Calendar não está acessível, com a ação que resolve.
struct CalendarIssueBanner: View {
    @Environment(TaskStore.self) private var store
    @Environment(GoogleAuth.self) private var auth
    @Environment(\.openURL) private var openURL

    var body: some View {
        if let issue = store.calendarIssue {
            Banner(symbol: "calendar.badge.exclamationmark", tint: .orange,
                   message: (issue.errorDescription ?? "Erro no Google Calendar")
                       + (issue.isServiceDisabled ? " Depois de ativar, leva 1–2 min para valer." : "")) {
                HStack(spacing: 6) {
                    if issue.isServiceDisabled, let url = issue.activationURL {
                        Button("Ativar") { openURL(url) }
                    } else if issue.isScopeInsufficient {
                        Button("Entrar de novo") {
                            auth.signOut()
                            store.reset()
                        }
                    }
                    Button("Tentar de novo") { Task { await store.syncEvents(force: true) } }
                }
                .controlSize(.small)
            }
        }
    }
}

struct Banner<Trailing: View>: View {
    let symbol: String
    let tint: Color
    let message: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: symbol).foregroundStyle(tint)
            Text(message)
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            trailing
        }
        .padding(10)
        .background(tint.opacity(0.09), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

struct EmptyState: View {
    let symbol: String
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: symbol).font(.system(size: 24)).foregroundStyle(.tertiary)
            Text(title).font(.callout.weight(.medium)).foregroundStyle(.secondary)
            if let subtitle { Text(subtitle).font(.caption).foregroundStyle(.tertiary) }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 26)
    }
}

/// Configura a janela do popover da barra de menu: tema escolhido (não o da barra) e
/// aviso de abertura/fechamento para animar a entrada.
struct PopoverWindowConfigurator: NSViewRepresentable {
    let appearance: NSAppearance?
    var onOpen: () -> Void = {}
    var onClose: () -> Void = {}

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { configure(view, context.coordinator) }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        context.coordinator.onOpen = onOpen
        context.coordinator.onClose = onClose
        DispatchQueue.main.async { configure(view, context.coordinator) }
    }

    private func configure(_ view: NSView, _ coordinator: Coordinator) {
        guard let window = view.window else { return }
        window.appearance = appearance
        coordinator.onOpen = onOpen
        coordinator.onClose = onClose
        coordinator.observe(window)
    }

    @MainActor
    final class Coordinator {
        var onOpen: () -> Void = {}
        var onClose: () -> Void = {}
        private weak var window: NSWindow?
        private var tokens: [NSObjectProtocol] = []

        func observe(_ window: NSWindow) {
            guard self.window !== window else { return }
            self.window = window
            for token in tokens { NotificationCenter.default.removeObserver(token) }
            let center = NotificationCenter.default
            tokens = [
                center.addObserver(forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.onOpen() }
                },
                center.addObserver(forName: NSWindow.didResignKeyNotification, object: window, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.onClose() }
                },
            ]
            onOpen()
        }
    }
}

/// Botão com feedback de hover (fundo suave) e clique (leve encolhida), com mola.
struct PressableStyle: ButtonStyle {
    var cornerRadius: CGFloat = 8
    var hoverFill: Color = Color.primary.opacity(0.07)

    func makeBody(configuration: Configuration) -> some View {
        PressableBody(configuration: configuration, cornerRadius: cornerRadius, hoverFill: hoverFill)
    }

    private struct PressableBody: View {
        let configuration: ButtonStyle.Configuration
        let cornerRadius: CGFloat
        let hoverFill: Color
        @State private var hovering = false

        var body: some View {
            configuration.label
                .background(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(hovering || configuration.isPressed ? hoverFill : .clear)
                )
                .scaleEffect(configuration.isPressed ? 0.92 : (hovering ? 1.04 : 1))
                .opacity(configuration.isPressed ? 0.8 : 1)
                .animation(.spring(response: 0.22, dampingFraction: 0.7), value: configuration.isPressed)
                .animation(.easeOut(duration: 0.12), value: hovering)
                .onHover { hovering = $0 }
        }
    }
}

extension ButtonStyle where Self == PressableStyle {
    static var pressable: PressableStyle { PressableStyle() }
}

private struct CheckPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.82 : 1)
            .animation(.spring(response: 0.2, dampingFraction: 0.6), value: configuration.isPressed)
    }
}
