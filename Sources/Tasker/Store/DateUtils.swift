import Foundation

enum RFC3339 {
    nonisolated(unsafe) private static let fractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    nonisolated(unsafe) private static let plain = ISO8601DateFormatter()

    static func date(_ string: String) -> Date? {
        fractional.date(from: string) ?? plain.date(from: string)
    }

    static func string(_ date: Date) -> String {
        plain.string(from: date)
    }
}

extension Calendar {
    /// Converte "yyyy-MM-dd..." em meia-noite local daquele dia.
    func day(fromISO string: String) -> Date? {
        let parts = string.prefix(10).split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    func adding(days: Int, to date: Date) -> Date {
        self.date(byAdding: .day, value: days, to: date) ?? date
    }
}

enum DayLabel {
    @MainActor private static var memo: [Date: [Date: String]] = [:]

    /// "Hoje", "Amanhã", "Ontem", "qua." ou "26 de out." — memorizado (a mesma data aparece em muitas linhas).
    @MainActor static func short(_ day: Date, today: Date) -> String {
        if let pronto = memo[today]?[day] { return pronto }
        if memo[today] == nil { memo = [:] }
        let rotulo = calcularShort(day, today: today)
        memo[today, default: [:]][day] = rotulo
        return rotulo
    }

    private static func calcularShort(_ day: Date, today: Date) -> String {
        let cal = Calendar.current
        let diff = cal.dateComponents([.day], from: today, to: day).day ?? 0
        switch diff {
        case 0: return "Hoje"
        case 1: return "Amanhã"
        case -1: return "Ontem"
        case 2...6: return day.formatted(.dateTime.weekday(.wide)).primeiraMaiuscula
        default:
            let sameYear = cal.component(.year, from: day) == cal.component(.year, from: today)
            return sameYear
                ? day.formatted(.dateTime.day().month(.abbreviated))
                : day.formatted(.dateTime.day().month(.abbreviated).year())
        }
    }

    /// "segunda-feira, 26 de out."
    static func long(_ day: Date) -> String {
        let text = day.formatted(.dateTime.weekday(.wide).day().month(.abbreviated))
        return text.prefix(1).uppercased() + text.dropFirst()
    }
}

extension String {
    /// "outubro de 2026" → "Outubro de 2026" (só a primeira letra).
    var primeiraMaiuscula: String { prefix(1).uppercased() + dropFirst() }
}
