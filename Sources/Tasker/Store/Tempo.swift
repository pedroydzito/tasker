import Foundation

/// Tempo gasto em cada tarefa: só o total (sem histórico de cada início e pausa)
/// e o cronômetro que está rodando agora. Fica só no Tasker.
struct TempoDB: Codable, Equatable {
    var total: [String: Double] = [:]  // taskID → segundos
    var ativo: String?
    var inicio: Date?

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        total = try c.decodeIfPresent([String: Double].self, forKey: .total) ?? [:]
        ativo = try c.decodeIfPresent(String.self, forKey: .ativo)
        inicio = try c.decodeIfPresent(Date.self, forKey: .inicio)
    }

    static var fileURL: URL { Pastas.base.appendingPathComponent("tempo.json") }

    static func load() -> TempoDB {
        guard let data = try? Data(contentsOf: fileURL), let db = try? JSONDecoder().decode(TempoDB.self, from: data)
        else { return TempoDB() }
        return db
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        try? data.write(to: Self.fileURL, options: .atomic)
    }
}

/// Formatar e ler durações ("1:05:09", "1h 05m", "20m", "1h20", "1:20").
enum Duracao {
    /// Cronômetro: "12:04" (até 1 h) ou "1:05:09".
    static func relogio(_ segundos: TimeInterval) -> String {
        let s = max(0, Int(segundos.rounded(.down)))
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%02d:%02d", m, sec)
    }

    /// Para resumos: "2h 15m", "45m", "30s".
    static func curto(_ segundos: TimeInterval) -> String {
        let s = max(0, Int(segundos.rounded(.down)))
        let h = s / 3600, m = (s % 3600) / 60
        if h > 0 { return m > 0 ? "\(h)h \(m)m" : "\(h)h" }
        if m > 0 { return "\(m)m" }
        return "\(s)s"
    }

    /// Lê o que a pessoa digitou. Número sozinho = minutos ("20" → 20 min).
    /// Aceita "1h", "1h20", "1h 20m", "90m", "45s", "1:20" (h:min) e "1:20:30".
    static func ler(_ texto: String) -> TimeInterval? {
        let t = texto.lowercased().replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: ",", with: ".")
        guard !t.isEmpty else { return nil }
        if t.contains(":") {
            let partes = t.split(separator: ":", omittingEmptySubsequences: false).map { Double($0) }
            guard partes.allSatisfy({ $0 != nil }), (2...3).contains(partes.count) else { return nil }
            let v = partes.compactMap { $0 }
            return v.count == 2 ? v[0] * 3600 + v[1] * 60 : v[0] * 3600 + v[1] * 60 + v[2]
        }
        if let minutos = Double(t) { return minutos * 60 }
        var total: Double = 0
        var numero = ""
        var achou = false
        for ch in t {
            if ch.isNumber || ch == "." {
                numero.append(ch)
                continue
            }
            guard let valor = Double(numero) else { return nil }
            switch ch {
            case "h": total += valor * 3600
            case "m": total += valor * 60
            case "s": total += valor
            default: return nil
            }
            numero = ""
            achou = true
        }
        if !numero.isEmpty {
            // "1h20": o que sobra depois das horas são minutos.
            guard let valor = Double(numero), achou else { return nil }
            total += valor * 60
        }
        return achou ? total : nil
    }
}
