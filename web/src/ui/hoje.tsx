import { CampoTarefa } from "./campo";
import { ArrowUpRight, BatteryFull, BatteryLow, ChevronDown, ChevronUp, Sun, Sunrise } from "lucide-react";
import { mesmaLista, usar } from "../dados/armazem";
import {
  adiarAtrasadas, 
  mudarPrefs, 
} from "../dados/acoes";
import { eventosDoDia, indice } from "../dados/consultas";
import type { Tarefa } from "../dados/tipos";
import { hojeISO, rotuloLongo, somarDias } from "../dados/util";
import { Cabecalho, CartaoLinhas, EstadoVazio, LinhaTarefa, Secao } from "./comuns";


export const raiz = (ts: Tarefa[]) => ts.filter((t) => !t.mae);
export const linhas = (ts: Tarefa[], opc: { data?: boolean; lista?: boolean } = {}) =>
  ts.map((t) => <LinhaTarefa key={t.id} t={t} mostrarData={opc.data ?? true} mostrarLista={opc.lista ?? true} />);
export const textoContagem = (n: number) => (n === 0 ? "Nada pendente" : `${n} tarefa${n === 1 ? "" : "s"} para concluir`);
const hora = (iso: string) => new Date(iso).toLocaleTimeString("pt-BR", { hour: "2-digit", minute: "2-digit" });


/** Eventos do Google Calendar (EventsCard): sem fundo, barra de cor, horário e título; seta recolhe. */
export function Eventos({ dia, compacto = false, recolhivel = true }: { dia: string; compacto?: boolean; recolhivel?: boolean }) {
  const evs = usar((e) => eventosDoDia(e, dia), mesmaLista);
  const fechado = usar((e) => e.prefs.eventosRecolhidos);
  if (!evs.length) return null;
  const mostrar = recolhivel && fechado ? evs.slice(0, 1) : evs;
  const agora = Date.now();
  return (
    <div style={{ display: "flex", alignItems: "flex-start" }}>
      <div style={{ flex: 1, minWidth: 0 }}>
        {mostrar.map((ev) => (
          <button key={ev.id} className="evento sem-veu sem-afundar" title="Abrir no Google Calendar" onClick={() => ev.link && abrirLink(ev.link)}
            style={{ ["--cor" as string]: ev.cor, padding: compacto ? "6px 0" : "7px 0", opacity: new Date(ev.fim).getTime() < agora ? 0.45 : 1 }}>
            <span className="evento-barra" />
            <span className="t-xs p-medio c3 numeros" style={{ minWidth: 74 }}>{ev.diaTodo ? "Dia todo" : `${hora(ev.inicio)}–${hora(ev.fim)}`}</span>
            <span className="t-sm p-medio uma-linha">{ev.titulo}</span>
            <ArrowUpRight size={10} strokeWidth={3} className="evento-seta" />
          </button>
        ))}
      </div>
      {recolhivel && evs.length > 1 && (
        <button className="icone-botao" style={{ width: 26, height: 26, marginTop: compacto ? 1 : 3 }} aria-label={fechado ? "Mostrar todos os eventos" : "Mostrar menos"}
          onClick={() => mudarPrefs((p) => ({ eventosRecolhidos: !p.eventosRecolhidos }))}>
          {fechado ? <ChevronDown size={11} /> : <ChevronUp size={11} />}
        </button>
      )}
    </div>
  );
}

function BotaoEnergia() {
  const baixa = usar((e) => e.prefs.energiaBaixa);
  return (
    <button className={"icone-botao" + (baixa ? " ativo" : "")} aria-label="Energia"
      title={baixa ? "Tô sem energia — clique para ver tudo" : "Tenho energia — clique se estiver sem energia"}
      onClick={() => mudarPrefs((p) => ({ energiaBaixa: !p.energiaBaixa }))}>
      {baixa ? <BatteryLow size={16} /> : <BatteryFull size={16} />}
    </button>
  );
}

export function TelaHoje() {
  const hoje = hojeISO();
  const baixa = usar((e) => e.prefs.energiaBaixa);
  const atrasadas = usar((e) => (e.prefs.energiaBaixa ? [] : raiz(indice(e).atrasadas)), mesmaLista);
  const tarefas = usar((e) => raiz(indice(e).hoje), mesmaLista);
  const feitas = usar((e) => indice(e).concluidasHoje, mesmaLista);
  const vazio = !tarefas.length && !atrasadas.length;
  const concluidas = feitas.length > 0 && (
    <Secao titulo="Concluídas" contagem={feitas.length} recolhida>{linhas(feitas, { data: false })}</Secao>
  );
  return (
    <>
      <Cabecalho titulo="Hoje" sub={baixa ? rotuloLongo(hoje) : `${rotuloLongo(hoje)} · ${textoContagem(atrasadas.length + tarefas.length)}`} direita={<BotaoEnergia />} />
      <div data-encadeado className="bloco-tela" style={{ ["--i" as string]: 1, display: "flex", flexDirection: "column", gap: "var(--e5)" }}>
        <CampoCelular prazo={hoje} />
        <Eventos dia={hoje} />
        {atrasadas.length > 0 && (
          <Secao titulo="Em atraso" contagem={atrasadas.length} tom="var(--perigo-texto)" acao={<button className="botao b-fantasma" onClick={adiarAtrasadas}>Mover para hoje</button>}>
            {linhas(atrasadas)}
          </Secao>
        )}
        {vazio && concluidas}
        {!tarefas.length ? (
          !atrasadas.length && <EstadoVazio Icone={Sun} titulo="Nada pendente" descricao="As tarefas com data de hoje aparecem aqui." />
        ) : !atrasadas.length ? (
          <CartaoLinhas>{linhas(tarefas, { data: false })}</CartaoLinhas>
        ) : (
          <Secao titulo="Hoje" contagem={tarefas.length}>{linhas(tarefas, { data: false })}</Secao>
        )}
        {!vazio && concluidas}
      </div>
    </>
  );
}

function Dia({ titulo, dia }: { titulo: string; dia: string }) {
  const ts = usar((e) => raiz(indice(e).porDia.get(dia) ?? []), mesmaLista);
  const temEventos = usar((e) => eventosDoDia(e, dia).length > 0);
  return (
    <>
      <Cabecalho titulo={titulo} sub={`${rotuloLongo(dia)} · ${textoContagem(ts.length)}`} />
      <div data-encadeado className="bloco-tela" style={{ ["--i" as string]: 1, display: "flex", flexDirection: "column", gap: "var(--e4)" }}>
        <CampoCelular prazo={dia} />
        {!ts.length && !temEventos ? (
          <EstadoVazio Icone={Sunrise} titulo="Dia livre" descricao={`Nada marcado para ${titulo.toLowerCase()}.`} />
        ) : (
          <>
            <Eventos dia={dia} />
            {ts.length > 0 && <CartaoLinhas>{linhas(ts, { data: false })}</CartaoLinhas>}
          </>
        )}
      </div>
    </>
  );
}

export function TelaAmanha() {
  return <Dia titulo="Amanhã" dia={somarDias(hojeISO(), 1)} />;
}


export function aplicarTema() {
  const t = localStorage.getItem("tasker.tema") || "sistema";
  const escuro = t === "escuro" || (t === "sistema" && matchMedia("(prefers-color-scheme: dark)").matches);
  document.documentElement.dataset.tema = escuro ? "escuro" : "claro";
  // A barra do sistema acompanha o --fundo computado (não um hexadecimal repetido).
  const fundo = getComputedStyle(document.documentElement).getPropertyValue("--fundo").trim();
  let meta = document.querySelector<HTMLMetaElement>("meta[data-tema-app]");
  if (!meta) {
    meta = document.createElement("meta");
    meta.name = "theme-color";
    meta.setAttribute("data-tema-app", "");
    document.head.appendChild(meta);
  }
  if (fundo) meta.content = fundo;
}


/** No celular, o campo de nova tarefa fica no alto da tela (como no menu do Mac), não na navegação. */
export function CampoCelular(p: { prazo?: string | null; listaId?: string | null; etiqueta?: string | null }) {
  return <div className="campo-celular"><CampoTarefa {...p} /></div>;
}

/** Link para fora: no app do Mac abre no navegador do sistema; na web, numa aba nova. */
export function abrirLink(url: string) {
  const p = (window as { webkit?: { messageHandlers?: { tasker?: { postMessage: (m: unknown) => void } } } }).webkit?.messageHandlers?.tasker;
  if (p) p.postMessage({ acao: "abrirLink", url });
  else window.open(url, "_blank", "noopener");
}
