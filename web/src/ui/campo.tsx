import { useEffect, useRef, useState } from "react";
import { ArrowUp, Calendar, List, Plus } from "lucide-react";
import { usar } from "../dados/armazem";
import { criarDoTexto } from "../dados/acoes";
import { listaPadrao } from "../dados/consultas";
import { hojeISO, lerCriacaoRapida, linhas, rotuloCurto } from "../dados/util";
import { Chip, ChipLista, DropdownListas, SeletorData } from "./comuns";

// Campo de nova tarefa (QuickAddField.swift): entende datas, ~lista e #etiqueta. Ao digitar,
// aparecem a lista, a data e as etiquetas; clicar na lista ou na data abre o seletor ali mesmo.
// Uma lista colada vira uma tarefa por linha.

export type EstiloCampo = "compacto" | "inline" | "flutuante";

export function CampoTarefa({ prazo = null, listaId = null, etiqueta = null, estilo = "compacto", placeholder, aoAdicionar, autoFoco = false }: {
  prazo?: string | null; listaId?: string | null; etiqueta?: string | null; estilo?: EstiloCampo; placeholder?: string; aoAdicionar?: () => void; autoFoco?: boolean;
}) {
  const e = usar((x) => x);
  const [texto, setTexto] = useState("");
  const [foco, setFoco] = useState(false);
  const [listaEscolhida, setListaEscolhida] = useState<string | null>(null);
  const [dataEscolhida, setDataEscolhida] = useState<string | null | undefined>(undefined);
  const [horario, setHorario] = useState<string | null>(null);
  const [dropdown, setDropdown] = useState(false);
  const [data, setData] = useState(false);
  const ref = useRef<HTMLTextAreaElement>(null);
  const hoje = hojeISO();

  useEffect(() => {
    const f = () => ref.current?.focus();
    window.addEventListener("tasker:nova", f);
    if (autoFoco) setTimeout(f, 50);
    return () => window.removeEventListener("tasker:nova", f);
  }, []);
  useEffect(() => {
    const t = ref.current;
    if (!t) return;
    t.style.height = "auto";
    t.style.height = Math.min(t.scrollHeight, 6 * 22) + "px";
    if (!texto) { setDropdown(false); setData(false); }
  }, [texto]);

  const lido = lerCriacaoRapida(texto, e.listas, hoje);
  const varias = linhas(texto);
  const lista = lido.listaId ?? listaEscolhida ?? listaId ?? listaPadrao(e);
  const due = lido.prazo !== undefined ? lido.prazo : dataEscolhida !== undefined ? dataEscolhida : prazo;

  const limpar = () => {
    setTexto(""); setListaEscolhida(null); setDataEscolhida(undefined); setHorario(null); setDropdown(false); setData(false);
    aoAdicionar?.();
  };
  const enviar = () => {
    if (!texto.trim()) return;
    criarDoTexto(texto, { prazo: due, listaId: listaEscolhida ?? listaId, etiqueta, horario: due ? horario : null });
    limpar();
  };
  const flutua = estilo === "flutuante";
  return (
    <div className={"campo-tarefa " + estilo + (foco ? " focado" : "")}>
      <div className="campo-tarefa-linha">
        <Plus size={13} strokeWidth={2.6} className="mais-campo" />
        <textarea ref={ref} rows={1} value={texto} aria-label="Adicionar tarefa" enterKeyHint="done"
          placeholder={placeholder ?? (flutua && !!(window as { webkit?: { messageHandlers?: { tasker?: unknown } } }).webkit?.messageHandlers?.tasker ? "Adicionar tarefa  ·  ⌥Espaço de qualquer lugar" : "Adicionar tarefa")}
          onFocus={() => setFoco(true)} onBlur={() => setFoco(false)} onChange={(x) => setTexto(x.target.value)}
          onKeyDown={(x) => {
            if (x.key === "Enter" && !x.shiftKey) { x.preventDefault(); enviar(); }
            if (x.key === "Escape") { if (dropdown || data) { setDropdown(false); setData(false); } else { setTexto(""); x.currentTarget.blur(); } }
          }} />
        {flutua && (
          <button className={"enviar sem-veu" + (texto.trim() ? " pronto" : "")} aria-label="Adicionar tarefa" title="Adicionar tarefa" disabled={!texto.trim()} onClick={enviar}>
            <ArrowUp size={12} strokeWidth={3} />
          </button>
        )}
      </div>
      {!!texto && (
        <div className="chips-campo entrar">
          {lista && (
            <button className="so-afunda sem-veu" title="Trocar a lista" onMouseDown={(x) => x.preventDefault()} onClick={() => { setDropdown(!dropdown); setData(false); }}>
              <ChipLista listaId={lista} comSeta aberta={dropdown} />
            </button>
          )}
          <button className="so-afunda sem-veu" title="Trocar a data" onMouseDown={(x) => x.preventDefault()} onClick={() => { setData(!data); setDropdown(false); }}>
            <Chip texto={(due ? rotuloCurto(due, hoje) : "Sem data") + (horario && due ? ` · ${horario}` : "")}><Calendar size={10} strokeWidth={2.6} /></Chip>
          </button>
          {varias.length > 1 && <span title="Uma tarefa por linha. Data e lista escritas na linha valem só para ela."><Chip texto={`${varias.length} tarefas`} cor="var(--acento)"><List size={10} strokeWidth={2.6} /></Chip></span>}
          {varias.length <= 1 && lido.etiquetas.map((n) => <Chip key={n} texto={"#" + n} cor={e.etiquetas.find((g) => g.nome.toLowerCase() === n.toLowerCase())?.cor ?? "var(--texto2)"} />)}
          <span style={{ flex: 1 }} />
          <span className="t-xs c3 so-desktop">↩︎ Adicionar</span>
        </div>
      )}
      {!!texto && data && (
        <div className="entrar" style={{ padding: "0 var(--e1) var(--e1)" }}>
          <SeletorData valor={due ?? null} horario={horario} aoEscolher={(d) => setDataEscolhida(d)} aoMudarHorario={setHorario} fechar={() => { setData(false); ref.current?.focus(); }} />
        </div>
      )}
      {!!texto && dropdown && (
        <div style={{ padding: "0 var(--e1) var(--e1)" }}>
          <DropdownListas atual={lista} aoEscolher={(id) => { setListaEscolhida(id); setDropdown(false); ref.current?.focus(); }} />
        </div>
      )}
    </div>
  );
}
