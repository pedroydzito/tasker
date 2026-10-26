import SwiftUI

enum Palette {
    static let lists = ["#8E5BE8", "#F2683C", "#2F80ED", "#27AE60", "#EB5757", "#E2B93B", "#2DB7C7", "#D45BB0", "#5E6AD2", "#8A8F98"]
}

extension Color {
    init(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        var value: UInt64 = 0
        Scanner(string: s).scanHexInt64(&value)
        self.init(.sRGB,
                  red: Double((value >> 16) & 0xFF) / 255,
                  green: Double((value >> 8) & 0xFF) / 255,
                  blue: Double(value & 0xFF) / 255)
    }

    var hexString: String {
        let c = NSColor(self).usingColorSpace(.sRGB) ?? .gray
        return String(format: "#%02X%02X%02X", Int(round(c.redComponent * 255)),
                      Int(round(c.greenComponent * 255)), Int(round(c.blueComponent * 255)))
    }
}

/// Círculo de conclusão colorido com a cor da lista.
struct CheckCircle: View {
    let color: Color
    let checked: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle().strokeBorder(color, lineWidth: 1.6)
                Circle().fill(color).opacity(checked ? 1 : (hovering ? 0.12 : 0))
                if checked || hovering {
                    Image(systemName: "checkmark")
                        .font(.system(size: 8.5, weight: .heavy))
                        .foregroundStyle(checked ? Color.white : color)
                }
            }
            .frame(width: 18, height: 18)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(checked ? "Reabrir" : "Concluir")
    }
}

struct SectionHeader: View {
    let title: String
    let count: Int
    var tint: Color = .secondary

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

struct Avatar: View {
    let profile: GoogleAuth.Profile?
    var size: CGFloat = 26

    var body: some View {
        AsyncImage(url: profile?.picture.flatMap(URL.init(string:))) { image in
            image.resizable().scaledToFill()
        } placeholder: {
            ZStack {
                Circle().fill(Color.accentColor.opacity(0.2))
                Text(String((profile?.name ?? profile?.email ?? "?").prefix(1)).uppercased())
                    .font(.system(size: size * 0.45, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }
}

struct DueBadge: View {
    let day: Date
    let today: Date
    var filled = false

    private var isOverdue: Bool { day < today }
    private var isToday: Bool { day == today }

    var body: some View {
        let label = DayLabel.short(day, today: today)
        let tint: Color = isOverdue ? .red : (isToday ? .accentColor : .secondary)
        if filled {
            Text(label)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(tint)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
        } else {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(isOverdue ? Color.red : Color.secondary)
        }
    }
}

struct ListBadge: View {
    let title: String
    let color: Color

    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(title).lineLimit(1)
        }
        .font(.system(size: 11.5))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
    }
}

/// Faixa discreta para erros de sincronização.
struct ErrorBanner: View {
    @Environment(TaskStore.self) private var store

    var body: some View {
        if let error = store.lastError {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                Text(error).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Button { store.lastError = nil } label: { Image(systemName: "xmark") }
                    .buttonStyle(.plain)
                    .foregroundStyle(.tertiary)
            }
            .padding(8)
            .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }
}

struct EmptyState: View {
    let symbol: String
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: symbol).font(.system(size: 26)).foregroundStyle(.tertiary)
            Text(title).font(.callout.weight(.medium)).foregroundStyle(.secondary)
            if let subtitle { Text(subtitle).font(.caption).foregroundStyle(.tertiary) }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
    }
}

/// Etiqueta local (só no app) — estilo pílula colorida como no TickTick.
struct TagChip: View {
    let name: String
    let color: Color

    var body: some View {
        Text(name)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(color)
            .lineLimit(1)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15), in: Capsule())
    }
}
