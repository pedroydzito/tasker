import Foundation

struct TaskList: Identifiable, Codable, Hashable {
    let id: String
    var title: String
}

struct TaskItem: Identifiable, Codable, Hashable {
    var id: String
    var listID: String
    var title: String
    var notes: String?
    var isCompleted: Bool
    var due: String? { didSet { dueDay = Self.parseDue(due) } }
    var completed: String? { didSet { completedDate = completed.flatMap(RFC3339.date) } }
    var parent: String?
    var position: String?
    var webViewLink: String?

    /// Datas já convertidas (guardadas para não reconverter texto a cada render/ordenação).
    /// O Google Tasks guarda só a data (em UTC); tratamos como um dia local.
    private(set) var dueDay: Date?
    private(set) var completedDate: Date?

    enum CodingKeys: String, CodingKey {
        case id, listID, title, notes, isCompleted, due, completed, parent, position, webViewLink
    }

    init(id: String, listID: String, title: String, notes: String? = nil, isCompleted: Bool = false,
         due: String? = nil, completed: String? = nil, parent: String? = nil, position: String? = nil,
         webViewLink: String? = nil) {
        self.id = id
        self.listID = listID
        self.title = title
        self.notes = notes
        self.isCompleted = isCompleted
        self.due = due
        self.completed = completed
        self.parent = parent
        self.position = position
        self.webViewLink = webViewLink
        dueDay = Self.parseDue(due)
        completedDate = completed.flatMap(RFC3339.date)
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(id: try c.decode(String.self, forKey: .id),
                  listID: try c.decode(String.self, forKey: .listID),
                  title: try c.decode(String.self, forKey: .title),
                  notes: try c.decodeIfPresent(String.self, forKey: .notes),
                  isCompleted: try c.decode(Bool.self, forKey: .isCompleted),
                  due: try c.decodeIfPresent(String.self, forKey: .due),
                  completed: try c.decodeIfPresent(String.self, forKey: .completed),
                  parent: try c.decodeIfPresent(String.self, forKey: .parent),
                  position: try c.decodeIfPresent(String.self, forKey: .position),
                  webViewLink: try c.decodeIfPresent(String.self, forKey: .webViewLink))
    }

    init(_ g: GTask, listID: String) {
        self.init(id: g.id, listID: listID, title: g.title ?? "", notes: g.notes,
                  isCompleted: g.status == "completed", due: g.due, completed: g.completed,
                  parent: g.parent, position: g.position, webViewLink: g.webViewLink)
    }

    private static func parseDue(_ due: String?) -> Date? {
        due.flatMap { Calendar.current.day(fromISO: $0) }
    }

    /// Tarefa criada localmente que ainda não voltou do servidor.
    var isLocal: Bool { id.hasPrefix("local-") }

    var displayTitle: String { title.isEmpty ? "(sem título)" : title }

    var hasNotes: Bool { !notasVisiveis.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    static func dueString(for day: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: day)
        return String(format: "%04d-%02d-%02dT00:00:00.000Z", c.year ?? 1970, c.month ?? 1, c.day ?? 1)
    }
}

struct CalendarInfo: Identifiable, Codable, Hashable {
    let id: String
    var title: String
    var colorHex: String
    var isPrimary: Bool
    var selectedInGoogle: Bool
}

struct CalendarEvent: Identifiable, Codable, Hashable {
    let id: String
    var calendarID: String
    var title: String
    var start: Date
    var end: Date
    var isAllDay: Bool
    var colorHex: String
    var htmlLink: String?

    init?(_ g: GEvent, calendar: CalendarInfo) {
        guard g.status != "cancelled",
              g.attendees?.first(where: { $0.isSelf == true })?.responseStatus != "declined"
        else { return nil }

        let cal = Calendar.current
        if let s = g.start?.dateTime.flatMap(RFC3339.date), let e = g.end?.dateTime.flatMap(RFC3339.date) {
            start = s
            end = e
            isAllDay = false
        } else if let s = g.start?.date.flatMap(cal.day(fromISO:)) {
            start = s
            end = g.end?.date.flatMap(cal.day(fromISO:)) ?? cal.adding(days: 1, to: s)
            isAllDay = true
        } else {
            return nil
        }

        id = "\(calendar.id)|\(g.id)"
        calendarID = calendar.id
        title = g.summary ?? "(sem título)"
        colorHex = g.colorId.flatMap { Self.eventColors[$0] } ?? calendar.colorHex
        htmlLink = g.htmlLink
    }

    func overlaps(dayStart: Date) -> Bool {
        let dayEnd = Calendar.current.adding(days: 1, to: dayStart)
        return start < dayEnd && end > dayStart
    }

    var timeLabel: String {
        if isAllDay { return "Dia todo" }
        return "\(Self.time.string(from: start))–\(Self.time.string(from: end))"
    }

    private static let time: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    /// Paleta de cores de evento do Google Calendar (colorId → hex).
    static let eventColors: [String: String] = [
        "1": "#7986CB", "2": "#33B679", "3": "#8E24AA", "4": "#E67C73", "5": "#F6BF26", "6": "#F4511E",
        "7": "#039BE5", "8": "#616161", "9": "#3F51B5", "10": "#0B8043", "11": "#D50000",
    ]
}

// MARK: Horário (sincronizado pelas notas)

/// O Google Tasks não guarda horário, então ele vai como a última linha das notas
/// ("Horário: 14:30") — aparece no Google e o Tasker o lê e esconde da descrição.
enum HorarioNasNotas {
    static let prefixo = "Horário: "

    static func separar(_ notas: String?) -> (texto: String, horario: String?) {
        guard let notas, !notas.isEmpty else { return ("", nil) }
        var linhas = notas.components(separatedBy: "\n")
        while let ultima = linhas.last, ultima.trimmingCharacters(in: .whitespaces).isEmpty { linhas.removeLast() }
        guard let ultima = linhas.last?.trimmingCharacters(in: .whitespaces), ultima.hasPrefix(prefixo) else {
            return (notas, nil)
        }
        let hora = String(ultima.dropFirst(prefixo.count)).trimmingCharacters(in: .whitespaces)
        guard hora.count == 5, hora.dropFirst(2).first == ":" else { return (notas, nil) }
        linhas.removeLast()
        while let fim = linhas.last, fim.trimmingCharacters(in: .whitespaces).isEmpty { linhas.removeLast() }
        return (linhas.joined(separator: "\n"), hora)
    }

    static func juntar(_ texto: String, _ horario: String?) -> String {
        let limpo = texto.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let horario else { return limpo }
        return limpo.isEmpty ? prefixo + horario : limpo + "\n\n" + prefixo + horario
    }
}

extension TaskItem {
    var horario: String? { HorarioNasNotas.separar(notes).horario }
    /// Notas sem a linha do horário (o que aparece como descrição).
    var notasVisiveis: String { HorarioNasNotas.separar(notes).texto }
}
