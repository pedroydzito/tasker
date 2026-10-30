import { definir, ler } from "./armazem";
import { mudarPrefs, salvarTarefa } from "./acoes";
import { sucesso } from "./avisos";
import { guardarArquivo } from "./espelho";
import { enfileirar } from "./fila";
import { puxar } from "./sync";
import type { Etiqueta, ItemDespejo, Nota } from "./tipos";

// Na primeira abertura do app do Mac com a interface web, o Swift entrega o que o app antigo
// guardava só no Mac (despejo, notas, etiquetas, tempos, horários, cores e ícones das listas).
// Junta sem apagar nada: o que já existe aqui (mesmo id) fica como está.

export interface DadosDoMac {
  etiquetas: { id: string; nome: string; cor: string }[];
  etiquetasDaTarefa: Record<string, string[]>;
  horarios: Record<string, string>;
  tempos: Record<string, number>;
  notas: {
    id: string;
    titulo: string;
    texto: string;
    dia: string | null;
    criada: string;
    editada: string;
    foto: string | null;
  }[];
  despejo: {
    id: string;
    texto: string;
    estado: "caixa" | "depois" | "nao";
    criado: string;
    movido: string | null;
    foto: string | null;
  }[];
  /** nome do arquivo → JPEG em base64 */
  fotos: Record<string, string>;
  coresListas: Record<string, string>;
  iconesListas: Record<string, string>;
  listaPadrao: string | null;
}

const pasta = () => localStorage.getItem("tasker.usuario") ?? "local";

function base64ParaBlob(b64: string): Blob {
  const bin = atob(b64);
  const bytes = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i);
  return new Blob([bytes], { type: "image/jpeg" });
}

export async function importarDoMac(d: DadosDoMac): Promise<number> {
  const e = ler();
  if (e.modo === "carregando" || e.modo === "entrar") return 0;
  let total = 0;
  // Tela de trabalho enquanto traz (§8.40): o que está acontecendo e uma barra, nada para clicar.
  const aviso = document.createElement("div");
  aviso.className = "tela-importando";
  aviso.setAttribute("role", "status");
  aviso.innerHTML =
    '<div class="cartao-importando"><strong>Trazendo seus dados do app do Mac…</strong><span>Notas, despejo, etiquetas e tempos. Leva alguns segundos.</span><div class="barra-espera"></div></div>';
  document.body.append(aviso);
  try {
    // Fotos: o caminho no bucket passa a ser <usuário>/<nome>.
    const caminhos = new Map<string, string>();
    for (const [nome, b64] of Object.entries(d.fotos ?? {})) {
      const caminho = `${pasta()}/${nome}`;
      caminhos.set(nome, caminho);
      await guardarArquivo(`fotos/${caminho}`, base64ParaBlob(b64));
      void enfileirar({
        tipo: "arquivo",
        bucket: "fotos",
        caminho,
        arquivoId: `fotos/${caminho}`,
        tipoArquivo: "image/jpeg",
      });
    }
    const foto = (n: string | null) => (n ? (caminhos.get(n) ?? null) : null);

    const etiquetas: Etiqueta[] = [...e.etiquetas];
    d.etiquetas.forEach((g, i) => {
      if (etiquetas.some((x) => x.id === g.id)) return;
      etiquetas.push({
        id: g.id,
        nome: g.nome,
        cor: g.cor,
        ordem: etiquetas.length + i,
      });
      void enfileirar({
        tipo: "tabela",
        tabela: "etiquetas",
        acao: "upsert",
        linha: {
          id: g.id,
          nome: g.nome,
          cor: g.cor,
          ordem: etiquetas.length + i,
        },
      });
      total++;
    });
    const etiquetasDaTarefa = { ...e.etiquetasDaTarefa };
    for (const [tarefa, ids] of Object.entries(d.etiquetasDaTarefa ?? {})) {
      const atuais = new Set(etiquetasDaTarefa[tarefa] ?? []);
      for (const id of ids)
        if (!atuais.has(id)) {
          atuais.add(id);
          void enfileirar({
            tipo: "tabela",
            tabela: "etiquetas_tarefas",
            acao: "upsert",
            linha: { tarefa_id: tarefa, etiqueta_id: id },
          });
        }
      etiquetasDaTarefa[tarefa] = [...atuais];
    }
    const tempos = { ...e.tempos };
    for (const [tarefa, s] of Object.entries(d.tempos ?? {})) {
      if ((tempos[tarefa] ?? 0) >= s) continue;
      tempos[tarefa] = s;
      void enfileirar({
        tipo: "tabela",
        tabela: "tempos",
        acao: "upsert",
        linha: { tarefa_id: tarefa, segundos: Math.round(s) },
      });
    }
    const notas: Nota[] = [...e.notas];
    for (const n of d.notas ?? []) {
      if (notas.some((x) => x.id === n.id || (n.dia && x.dia === n.dia)))
        continue;
      const nota: Nota = {
        id: n.id,
        titulo: n.titulo,
        texto: n.texto,
        dia: n.dia,
        foto: foto(n.foto),
        criadaEm: n.criada,
        editadaEm: n.editada,
      };
      notas.push(nota);
      void enfileirar({
        tipo: "tabela",
        tabela: "notas",
        acao: "upsert",
        linha: {
          id: nota.id,
          titulo: nota.titulo,
          texto: nota.texto,
          dia: nota.dia,
          foto: nota.foto,
          criada_em: nota.criadaEm,
          editada_em: nota.editadaEm,
        },
      });
      total++;
    }
    const despejo: ItemDespejo[] = [...e.despejo];
    for (const i of d.despejo ?? []) {
      if (despejo.some((x) => x.id === i.id)) continue;
      const item: ItemDespejo = {
        id: i.id,
        texto: i.texto,
        estado: i.estado,
        foto: foto(i.foto),
        criadoEm: i.criado,
        movidoEm: i.movido,
      };
      despejo.push(item);
      void enfileirar({
        tipo: "tabela",
        tabela: "despejo",
        acao: "upsert",
        linha: {
          id: item.id,
          texto: item.texto,
          estado: item.estado,
          foto: item.foto,
          criado_em: item.criadoEm,
          movido_em: item.movidoEm,
        },
      });
      total++;
    }
    definir({ etiquetas, etiquetasDaTarefa, tempos, notas, despejo });
    mudarPrefs((p) => ({
      coresListas: { ...d.coresListas, ...p.coresListas },
      iconesListas: { ...d.iconesListas, ...p.iconesListas },
      listaPadrao: p.listaPadrao ?? d.listaPadrao,
    }));

    // Horários ficavam no app do Mac; aqui vão na descrição da tarefa (e para o Google).
    // Espera as tarefas chegarem do Google para aplicar.
    await puxar(true);
    for (const [tarefa, h] of Object.entries(d.horarios ?? {})) {
      const t = ler().tarefas[tarefa];
      if (t && t.prazo && !t.notas.includes("Horário:"))
        salvarTarefa(tarefa, { horario: h });
    }
    if (total) sucesso(`${total} itens trazidos do app do Mac`);
    return total;
  } finally {
    aviso.remove();
  }
}
