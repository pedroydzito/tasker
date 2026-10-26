import SwiftUI

// MARK: Sistema de design

/// Tokens de cor do Tasker (claro/escuro).
enum Theme {
    static let canvas = dynamic(light: "#F7F7F8", dark: "#151517")
    static let surface = dynamic(light: "#FFFFFF", dark: "#1F1F22")
    static let group = dynamic(light: "#F0F0F2", dark: "#1A1A1D")
    static let stroke = dynamic(light: "#E6E6EA", dark: "#2C2C31")
    static let subtle = dynamic(light: "#85858E", dark: "#8E8E97")
    static let field = dynamic(light: "#EFEFF2", dark: "#29292D")
    static let hover = dynamic(light: "#0000000D", dark: "#FFFFFF12")
    static let eventFill = dynamic(light: "#EAF1FD", dark: "#1F2737")

    static func dynamic(light: String, dark: String) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? NSColor(hex: dark) : NSColor(hex: light)
        })
    }
}

enum Palette {
    static let lists = ["#8E5BE8", "#F2683C", "#2F80ED", "#27AE60", "#EB5757", "#E2A93B", "#2DB7C7", "#D45BB0", "#5E6AD2", "#8A8F98"]
    static let emojis = ["🎨", "💼", "🏠", "📚", "💪", "🎬", "🛒", "✈️", "💡", "🧠", "📈", "🧾",
                         "🎵", "❤️", "⭐️", "🔥", "🧑‍💻", "📷", "🗂️", "🌱", "🍽️", "🎯", "📞", "🚀"]
}

extension NSColor {
    /// Aceita #RRGGBB ou #RRGGBBAA.
    convenience init(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        var value: UInt64 = 0
        Scanner(string: s).scanHexInt64(&value)
        if s.count == 8 {
            self.init(srgbRed: CGFloat((value >> 24) & 0xFF) / 255, green: CGFloat((value >> 16) & 0xFF) / 255,
                      blue: CGFloat((value >> 8) & 0xFF) / 255, alpha: CGFloat(value & 0xFF) / 255)
        } else {
            self.init(srgbRed: CGFloat((value >> 16) & 0xFF) / 255, green: CGFloat((value >> 8) & 0xFF) / 255,
                      blue: CGFloat(value & 0xFF) / 255, alpha: 1)
        }
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

    /// Versão legível da cor para texto sobre o fundo claro da própria cor.
    var ink: Color {
        let base = NSColor(self).usingColorSpace(.sRGB) ?? .gray
        return Color(nsColor: NSColor(name: nil) { appearance in
            let dark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return base.blended(withFraction: dark ? 0.35 : 0.4, of: dark ? .white : .black) ?? base
        })
    }
}

/// Fundo de vidro do macOS (vibrancy por trás da janela).
struct GlassBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .popover
    var cornerRadius: CGFloat = 0

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.blendingMode = .behindWindow
        view.state = .active
        update(view)
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        update(view)
    }

    private func update(_ view: NSVisualEffectView) {
        view.material = material
        view.maskImage = cornerRadius > 0 ? .roundedMask(radius: cornerRadius) : nil
    }
}

extension NSImage {
    /// Máscara esticável com cantos arredondados (para NSVisualEffectView).
    static func roundedMask(radius: CGFloat) -> NSImage {
        let side = radius * 2 + 1
        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }
}

// MARK: Botões

/// Botão discreto: fundo suave no hover, encolhe no clique.
struct PressableStyle: ButtonStyle {
    var cornerRadius: CGFloat = 8

    func makeBody(configuration: Configuration) -> some View {
        HoverBody(configuration: configuration) { pressed, hovering in
            configuration.label
                .background(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(pressed || hovering ? Theme.hover : .clear))
                .scaleEffect(pressed ? 0.94 : 1)
        }
    }
}

/// Botão secundário (cinza claro).
struct SoftButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        HoverBody(configuration: configuration) { pressed, hovering in
            configuration.label
                .font(.system(size: 12.5, weight: .medium))
                .padding(.horizontal, 11)
                .padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Theme.field)
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(hovering ? Theme.hover : .clear)))
                .scaleEffect(pressed ? 0.96 : 1)
        }
    }
}

/// Botão principal (cor de destaque).
struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        HoverBody(configuration: configuration) { pressed, hovering in
            configuration.label
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.accentColor)
                    .brightness(hovering ? 0.06 : 0))
                .scaleEffect(pressed ? 0.96 : 1)
        }
    }
}

/// Junta hover + clique com animação de mola, para os estilos acima.
private struct HoverBody<Content: View>: View {
    let configuration: ButtonStyle.Configuration
    @ViewBuilder let content: (Bool, Bool) -> Content
    @State private var hovering = false
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        content(configuration.isPressed, hovering && isEnabled)
            .opacity(isEnabled ? 1 : 0.45)
            .animation(.spring(response: 0.22, dampingFraction: 0.7), value: configuration.isPressed)
            .animation(.easeOut(duration: 0.12), value: hovering)
            .onHover { hovering = $0 }
    }
}

extension ButtonStyle where Self == PressableStyle {
    static var pressable: PressableStyle { PressableStyle() }
}

extension ButtonStyle where Self == SoftButtonStyle {
    static var soft: SoftButtonStyle { SoftButtonStyle() }
}

extension ButtonStyle where Self == PrimaryButtonStyle {
    static var primary: PrimaryButtonStyle { PrimaryButtonStyle() }
}

extension View {
    /// Campo de texto no estilo do app.
    func fieldStyle() -> some View {
        textFieldStyle(.plain)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Theme.field, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    /// Ícone de ação redondinho (barra de ferramentas, cabeçalhos).
    func iconButtonLabel(size: CGFloat = 28) -> some View {
        font(.system(size: 13, weight: .medium))
            .foregroundStyle(.secondary)
            .frame(width: size, height: size)
            .contentShape(Rectangle())
    }
}

// MARK: Listas

/// Ícone da lista: azulejo arredondado na cor da lista com foto, emoji ou inicial.
struct ListIconView: View {
    @Environment(TaskStore.self) private var store
    let listID: String
    var size: CGFloat = 20

    var body: some View {
        let radius = size * 0.3
        let color = store.color(forList: listID)
        Group {
            if let photo = store.photo(forList: listID) {
                Image(nsImage: photo).resizable().scaledToFill()
            } else {
                ZStack {
                    color.opacity(0.18)
                    if let emoji = store.emoji(forList: listID) {
                        Text(emoji).font(.system(size: size * 0.6))
                    } else {
                        Text(String(store.displayName(listID).prefix(1)).uppercased())
                            .font(.system(size: size * 0.5, weight: .bold, design: .rounded))
                            .foregroundStyle(color.ink)
                    }
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

/// Pílula da lista: fundo na cor da lista, só o nome.
struct ListChip: View {
    @Environment(TaskStore.self) private var store
    let listID: String

    var body: some View {
        let color = store.color(forList: listID)
        Text(store.displayName(listID))
            .lineLimit(1)
            .font(.system(size: 11.5, weight: .medium))
            .foregroundStyle(color.ink)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.16), in: Capsule())
    }
}

/// Editor de aparência da lista: ícone (emoji, foto ou inicial) e cor.
struct ListAppearanceEditor: View {
    @Environment(TaskStore.self) private var store
    let listID: String
    @State private var customEmoji = ""

    private let columns = Array(repeating: GridItem(.fixed(30), spacing: 6), count: 8)

    var body: some View {
        let current = store.emoji(forList: listID)
        let color = store.color(forList: listID)
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                ListIconView(listID: listID, size: 54)
                    .shadow(color: color.opacity(0.25), radius: 8, y: 3)
                VStack(alignment: .leading, spacing: 6) {
                    Text(store.displayName(listID)).font(.system(size: 17, weight: .semibold))
                    ListChip(listID: listID)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                EditorLabel("Ícone")
                LazyVGrid(columns: columns, alignment: .leading, spacing: 6) {
                    ForEach(Palette.emojis, id: \.self) { emoji in
                        Button {
                            store.removePhoto(forList: listID)
                            store.setEmoji(emoji, forList: listID)
                        } label: {
                            Text(emoji)
                                .font(.system(size: 17))
                                .frame(width: 30, height: 30)
                                .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .fill(current == emoji && store.photo(forList: listID) == nil ? color.opacity(0.22) : .clear))
                        }
                        .buttonStyle(PressableStyle(cornerRadius: 7))
                    }
                }
                HStack(spacing: 6) {
                    TextField("Outro", text: $customEmoji)
                        .fieldStyle()
                        .frame(width: 64)
                        .onSubmit(applyCustomEmoji)
                        .onChange(of: customEmoji) { _, _ in applyCustomEmoji() }
                    Button { NSApp.orderFrontCharacterPalette(nil) } label: { Image(systemName: "face.smiling") }
                        .buttonStyle(.soft)
                        .help("Abrir emojis do macOS")
                    Button { choosePhoto() } label: { Label("Foto", systemImage: "photo") }
                        .buttonStyle(.soft)
                    Button {
                        store.removePhoto(forList: listID)
                        store.setEmoji(nil, forList: listID)
                    } label: { Text("Inicial") }
                        .buttonStyle(.soft)
                        .help("Usar só a inicial do nome")
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                EditorLabel("Cor")
                ColorSwatches(selection: Binding(
                    get: { color.hexString },
                    set: { store.setColor(Color(hex: $0), forList: listID) }
                ))
            }
        }
        .padding(18)
        .frame(width: 320)
    }

    private func applyCustomEmoji() {
        guard let first = customEmoji.first else { return }
        store.removePhoto(forList: listID)
        store.setEmoji(String(first), forList: listID)
        if customEmoji.count > 1 { customEmoji = String(first) }
    }

    private func choosePhoto() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.message = "Escolha uma foto para \(store.displayName(listID))"
        if panel.runModal() == .OK, let url = panel.url {
            store.setPhoto(from: url, forList: listID)
        }
    }
}

struct EditorLabel: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10.5, weight: .semibold))
            .tracking(0.8)
            .foregroundStyle(Theme.subtle)
    }
}

/// Amostras de cor + seletor livre.
struct ColorSwatches: View {
    @Binding var selection: String

    var body: some View {
        HStack(spacing: 7) {
            ForEach(Palette.lists, id: \.self) { hex in
                let selected = hex.uppercased() == selection.uppercased()
                Button { selection = hex } label: {
                    Circle()
                        .fill(Color(hex: hex))
                        .frame(width: 20, height: 20)
                        .overlay(Circle().strokeBorder(.white.opacity(0.9), lineWidth: selected ? 2 : 0).padding(2))
                        .overlay(Circle().strokeBorder(Color(hex: hex), lineWidth: selected ? 1.5 : 0).padding(-2))
                }
                .buttonStyle(PressableStyle(cornerRadius: 12))
            }
            ColorPicker("", selection: Binding(
                get: { Color(hex: selection) },
                set: { selection = $0.hexString }
            ), supportsOpacity: false)
            .labelsHidden()
            .help("Outra cor")
        }
    }
}

/// Criação de etiqueta local (nome + cor).
struct TagCreator: View {
    @Environment(TaskStore.self) private var store
    var onCreate: (Tag) -> Void = { _ in }
    @State private var name = ""
    @State private var color = Palette.lists[2]
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Nova etiqueta").font(.system(size: 14, weight: .semibold))
            TextField("Nome", text: $name)
                .fieldStyle()
                .focused($focused)
                .onSubmit(create)
            ColorSwatches(selection: $color)
            HStack {
                Text("Fica só no Tasker").font(.system(size: 11)).foregroundStyle(Theme.subtle)
                Spacer()
                Button("Criar", action: create).buttonStyle(.primary).disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(16)
        .frame(width: 290)
        .onAppear { focused = true }
    }

    private func create() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let tag = store.createTag(name: trimmed, colorHex: color)
        name = ""
        onCreate(tag)
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

/// Configura a janela do popover da barra de menu: tema escolhido (não o da barra),
/// janela transparente com cantos arredondados (para o vidro) e aviso de abertura.
struct PopoverWindowConfigurator: NSViewRepresentable {
    let appearance: NSAppearance?
    var cornerRadius: CGFloat = 16
    var onOpen: () -> Void = {}

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { configure(view, context.coordinator) }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        context.coordinator.onOpen = onOpen
        DispatchQueue.main.async { configure(view, context.coordinator) }
    }

    private func configure(_ view: NSView, _ coordinator: Coordinator) {
        guard let window = view.window else { return }
        window.appearance = appearance
        coordinator.onOpen = onOpen
        coordinator.attach(window, cornerRadius: cornerRadius)
    }

    @MainActor
    final class Coordinator {
        var onOpen: () -> Void = {}
        private weak var window: NSWindow?
        private var token: NSObjectProtocol?

        func attach(_ window: NSWindow, cornerRadius: CGFloat) {
            guard self.window !== window else { return }
            self.window = window
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = true
            window.animationBehavior = .none // abre instantâneo
            if let content = window.contentView {
                content.wantsLayer = true
                content.layer?.cornerRadius = cornerRadius
                content.layer?.cornerCurve = .continuous
                content.layer?.masksToBounds = true
                Self.roundEffectViews(in: content.superview ?? content, radius: cornerRadius)
            }
            window.invalidateShadow()

            if let token { NotificationCenter.default.removeObserver(token) }
            token = NotificationCenter.default.addObserver(
                forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.onOpen() }
            }
            onOpen()
        }

        /// O vidro do sistema por trás do conteúdo também ganha os cantos arredondados.
        private static func roundEffectViews(in view: NSView, radius: CGFloat, depth: Int = 0) {
            if let effect = view as? NSVisualEffectView {
                effect.maskImage = .roundedMask(radius: radius)
                effect.state = .active
            }
            guard depth < 4 else { return }
            for sub in view.subviews { roundEffectViews(in: sub, radius: radius, depth: depth + 1) }
        }
    }
}

private struct CheckPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.82 : 1)
            .animation(.spring(response: 0.2, dampingFraction: 0.6), value: configuration.isPressed)
    }
}
