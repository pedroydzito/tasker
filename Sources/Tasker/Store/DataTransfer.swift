import AppKit
import Foundation

/// Exportar e importar tudo (listas, tarefas, etiquetas e aparência das listas) num arquivo .json,
/// para levar a outro Mac ou mudar do modo local para o Google — sem servidor.
struct ArquivoTasker: Codable {
    struct Lista: Codable {
        var titulo: String
        var corHex: String?
        var simbolo: String?
        var fotoPNG: Data?
        var tarefas: [Tarefa]
    }

    struct Tarefa: Codable {
        var titulo: String
        var notas: String?
        var prazo: String?
        var concluida: Bool
        var etiquetas: [String] // nomes
    }

    var versao = 1
    var exportadoEm = Date()
    var etiquetas: [Tag]
    var listas: [Lista]
}

extension TaskStore {
    func exportar(para url: URL) throws {
        var listas: [ArquivoTasker.Lista] = []
        let porLista = Dictionary(grouping: tasks.values.filter { !$0.isLocal }, by: \.listID)
        for list in lists {
            let foto = photo(forList: list.id).flatMap { img -> Data? in
                guard let tiff = img.tiffRepresentation else { return nil }
                return NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
            }
            let tarefas = (porLista[list.id] ?? []).map { task in
                ArquivoTasker.Tarefa(titulo: task.title, notas: task.notes, prazo: task.due,
                                     concluida: task.isCompleted, etiquetas: tags(for: task).map(\.name))
            }
            listas.append(.init(titulo: list.title, corHex: prefs.listColors[list.id], simbolo: symbol(forList: list.id),
                                fotoPNG: foto, tarefas: tarefas))
        }
        let arquivo = ArquivoTasker(etiquetas: tags, listas: listas)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(arquivo).write(to: url, options: .atomic)
    }

    /// Junta o arquivo ao que já existe: listas com o mesmo nome recebem as tarefas.
    /// Devolve quantas tarefas foram importadas.
    func importar(de url: URL) async throws -> Int {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let arquivo = try decoder.decode(ArquivoTasker.self, from: Data(contentsOf: url))

        for tag in arquivo.etiquetas where !tags.contains(where: { $0.name.lowercased() == tag.name.lowercased() }) {
            createTag(name: tag.name, colorHex: tag.colorHex)
        }

        var total = 0
        for lista in arquivo.listas {
            let listID: String
            if let existente = lists.first(where: { $0.title.lowercased() == lista.titulo.lowercased() }) {
                listID = existente.id
            } else if let nova = await createList(title: lista.titulo, symbol: lista.simbolo, colorHex: lista.corHex) {
                listID = nova
            } else {
                continue
            }
            if let png = lista.fotoPNG, photo(forList: listID) == nil {
                let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).png")
                try? png.write(to: tmp)
                setPhoto(from: tmp, forList: listID)
                try? FileManager.default.removeItem(at: tmp)
            }
            // Importar o mesmo arquivo de novo não duplica: pula o que já existe (mesmo título e data).
            var existentes = Set(tasks.values.filter { $0.listID == listID }
                .map { "\($0.title.lowercased())|\($0.due?.prefix(10) ?? "")" })
            for tarefa in lista.tarefas {
                let chave = "\(tarefa.titulo.lowercased())|\(tarefa.prazo?.prefix(10) ?? "")"
                guard existentes.insert(chave).inserted else { continue }
                var criada = try await backend.insertTask(listID: listID, title: tarefa.titulo, notes: tarefa.notas, due: tarefa.prazo)
                if tarefa.concluida {
                    criada = try await backend.patchTask(listID: listID, taskID: criada.id, fields: ["status": "completed"])
                }
                let item = TaskItem(criada, listID: listID)
                for nome in tarefa.etiquetas {
                    if let tag = tags.first(where: { $0.name.lowercased() == nome.lowercased() }) {
                        toggleTag(tag, on: item)
                    }
                }
                total += 1
            }
        }
        await sync(force: true)
        return total
    }
}
