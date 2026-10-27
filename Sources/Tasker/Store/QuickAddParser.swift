import Foundation

/// Entende datas, listas e etiquetas digitadas no título, ao estilo TickTick:
/// "Ligar pro cliente amanhã ~trabalho #urgente", "Pagar boleto sexta", "Reunião 30/10", "Ideia sem data".
/// `~lista` escolhe a lista do Google Tasks; `#etiqueta` adiciona uma etiqueta local (só no app).
struct QuickAddParser {
    struct Result: Equatable {
        var title: String
        /// nil = não especificado; .some(nil) = "sem data" explícito.
        var due: Date??
        var listID: String?
        var tagNames: [String] = []
    }

    static func parse(_ text: String, lists: [TaskList], today: Date) -> Result {
        let cal = Calendar.current
        var tokens = text.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        var due: Date??
        var listID: String?
        var tagNames: [String] = []

        func fold(_ s: String) -> String {
            s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "pt_BR"))
                .trimmingCharacters(in: .punctuationCharacters)
        }

        // #etiqueta (pode haver várias)
        tokens.removeAll { token in
            guard token.hasPrefix("#"), token.count > 1 else { return false }
            tagNames.append(String(token.dropFirst()))
            return true
        }

        // ~lista
        if let index = tokens.firstIndex(where: { $0.hasPrefix("~") && $0.count > 1 }) {
            let query = fold(String(tokens[index].dropFirst()))
            if let match = lists.first(where: { fold(normalizedListName($0.title)).hasPrefix(query) }) {
                listID = match.id
                tokens.remove(at: index)
            }
        }

        let folded = tokens.map(fold)

        // Frases de mais de uma palavra primeiro.
        let phrases: [([String], Date?)] = [
            (["depois", "de", "amanha"], cal.adding(days: 2, to: today)),
            (["sem", "data"], nil),
        ]
        for (phrase, value) in phrases {
            if let range = find(phrase, in: folded) {
                due = .some(value)
                tokens.removeSubrange(range)
                return Result(title: tokens.joined(separator: " "), due: due, listID: listID, tagNames: tagNames)
            }
        }

        let weekdays: [String: Int] = [
            "domingo": 1, "segunda": 2, "segunda-feira": 2, "terca": 3, "terca-feira": 3,
            "quarta": 4, "quarta-feira": 4, "quinta": 5, "quinta-feira": 5,
            "sexta": 6, "sexta-feira": 6, "sabado": 7,
        ]

        for (i, word) in folded.enumerated() {
            var value: Date?
            if word == "hoje" {
                value = today
            } else if word == "amanha" {
                value = cal.adding(days: 1, to: today)
            } else if let weekday = weekdays[word] {
                let current = cal.component(.weekday, from: today)
                var diff = (weekday - current + 7) % 7
                if diff == 0 { diff = 7 }
                value = cal.adding(days: diff, to: today)
            } else if let date = parseNumericDate(word, today: today) {
                value = date
            }
            if let value {
                // "na sexta", "pra amanhã": remove a preposição junto.
                var range = i...i
                if i > 0, ["na", "no", "pra", "para", "em", "ate"].contains(folded[i - 1]) { range = (i - 1)...i }
                tokens.removeSubrange(range)
                due = .some(value)
                break
            }
        }

        return Result(title: tokens.joined(separator: " "), due: due, listID: listID, tagNames: tagNames)
    }

    private static func find(_ phrase: [String], in words: [String]) -> Range<Int>? {
        guard words.count >= phrase.count else { return nil }
        for start in 0...(words.count - phrase.count) where Array(words[start..<start + phrase.count]) == phrase {
            return start..<start + phrase.count
        }
        return nil
    }

    /// "30/10" ou "30/10/2026". Sem ano → próxima ocorrência.
    private static func parseNumericDate(_ word: String, today: Date) -> Date? {
        let parts = word.split(separator: "/").compactMap { Int($0) }
        guard (2...3).contains(parts.count), (1...31).contains(parts[0]), (1...12).contains(parts[1]) else { return nil }
        let cal = Calendar.current
        var year = parts.count == 3 ? parts[2] : cal.component(.year, from: today)
        if year < 100 { year += 2000 }
        // Recusa datas que não existem ("31/02" não vira 3 de março).
        guard var date = cal.date(from: DateComponents(year: year, month: parts[1], day: parts[0])),
              cal.component(.day, from: date) == parts[0], cal.component(.month, from: date) == parts[1]
        else { return nil }
        if parts.count == 2, date < today, let next = cal.date(byAdding: .year, value: 1, to: date) { date = next }
        return date
    }

    /// Remove emojis/símbolos do início do nome da lista ("🎨 Taís" → "Taís").
    static func normalizedListName(_ name: String) -> String {
        String(name.unicodeScalars.filter { $0.properties.isAlphabetic || $0.properties.numericType != nil || $0 == " " })
            .trimmingCharacters(in: .whitespaces)
    }
}
