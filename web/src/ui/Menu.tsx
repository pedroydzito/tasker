import { useEffect, useRef, useState } from "react";
import { Brain, CalendarDays, ChevronLeft, ChevronRight, CircleCheck, CircleUserRound, Eye, Maximize2, Plus, Settings, Sun, Trash2 } from "lucide-react";
import { mesmaLista, usar } from "../dados/armazem";
import { adiarAtrasadas, criarDoTexto, excluirTarefa, moverTarefa, salvarTarefa } from "../dados/acoes";
import { eventosDoDia, horarioDe, indice, notasVisiveis, tituloDe } from "../dados/consultas";
import { ponteMac, puxar } from "../dados/sync";
import type { Tarefa } from "../dados/tipos";
import { deISO, hojeISO, rotuloComAtraso, somarDias } from "../dados/util";
import { CartaoLinhas, Chip, ChipLista, DetalheNoMenuCtx, DropdownListas, EstadoVazio, LinhaTarefa, Secao, SeletorData } from "./comuns";
import { folhas, HospedeDeFolhas } from "./folhas";
import { CampoTempo, Subtarefas } from "./Inspetor";
import { AcoesRapidas, CampoDespejo, Eventos } from "./telas";
import type { Rota } from "./rota";

// Menu da barra do Mac (MenuBarPopover.swift): abas Hoje, Calendário e Despejo numa pílula,
// tamanho fixo, conteúdo rolável. Clicar numa tarefa abre os detalhes embaixo da linha.

type Aba = "hoje" | "calendario" | "despejo";

/** Pede ao app do Mac para abrir a janela grande numa tela (e, se quiser, numa tarefa). */
export function abrirNaJanela(rota: Rota, tarefa?: string) {
  const r = "#/" + rota.tela + ("id" in rota ? "/" + encodeURIComponent(rota.id) : "");
  const ponte = ponteMac();
  if (ponte) ponte.postMessage({ acao: "abrirJanela", rota: r, tarefa: tarefa ?? null });
  else location.hash = r;
}

function CampoRapidoMenu({ prazo }: { prazo: string }) {
  const [texto, setTexto] = useState("");
  const ref = useRef<HTMLInputElement>(null);
  useEffect(() => {
    const f = () => ref.current?.focus();
    window.addEventListener("tasker:nova", f);
    return () => window.removeEventListener("tasker:nova", f);
  }, []);
  return (
    <div className="campo-menu">
      <Plus size={14} className="c3" />
      <input ref={ref} placeholder="Adicionar tarefa" aria-label="Adicionar tarefa" value={texto} onChange={(e) => setTexto(e.target.value)}
        onKeyDown={(e) => { if (e.key === "Enter" && texto.trim()) { criarDoTexto(texto, { prazo }); setTexto(""); } if (e.key === "Escape") setTexto(""); }} />
    </div>
  );
}

/** Detalhes abertos embaixo da linha: lista e data (clicáveis), tempo, notas e subtarefas. */
function DetalheNoMenu({ t, fechar }: { t: Tarefa; fechar: () => void }) {
  const atual = usar((e) => e.tarefas[t.id] ?? t);
  const [dataAberta, setDataAberta] = useState(false);
  const [listasAbertas, setListasAbertas] = useState(false);
  const hoje = hojeISO();
  const horario = horarioDe(atual);
  const notas = notasVisiveis(atual).trim();
  return (
    <div className="detalhe-menu entrar" style={{ paddingLeft: 12 + (atual.mae ? 26 : 0) + 30 }} onClick={(e) => e.stopPropagation()}>
      <div style={{ display: "flex", flexWrap: "wrap", gap: "var(--e2)", alignItems: "center" }}>
        <button className="afunda" title="Mudar de lista" disabled={atual.provisoria} onClick={() => { setListasAbertas(!listasAbertas); setDataAberta(false); }}><ChipLista listaId={atual.listaId} comSeta aberta={listasAbertas} /></button>
        <button className="afunda" title="Mudar data e horário" onClick={() => { setDataAberta(!dataAberta); setListasAbertas(false); }}>
          <Chip texto={atual.prazo ? rotuloComAtraso(atual.prazo, hoje) + (horario ? ` · ${horario}` : "") : "Sem data"} cor={atual.prazo && atual.prazo < hoje ? "var(--perigo-texto)" : undefined}>
            <CalendarDays size={10} strokeWidth={2.6} />
          </Chip>
        </button>
        <span style={{ flex: 1 }} />
        <button className="icone-botao" style={{ width: 24, height: 24 }} title="Ver no app (descrição, etiquetas e mais)" onClick={() => abrirNaJanela(atual.concluida ? { tela: "concluidas" } : { tela: "lista", id: atual.listaId }, atual.id)}><Eye size={11} /></button>
        <button className="icone-botao" style={{ width: 24, height: 24 }} title="Excluir tarefa" onClick={() => folhas.confirmar("Excluir tarefa", `“${tituloDe(atual)}” será excluída. Dá para desfazer logo depois.`, () => { excluirTarefa(atual.id); fechar(); })}><Trash2 size={11} /></button>
      </div>
      {listasAbertas && <DropdownListas atual={atual.listaId} aoEscolher={(id) => { setListasAbertas(false); moverTarefa(atual.id, id); }} />}
      {dataAberta && (
        <SeletorData valor={atual.prazo} horario={horario} aoEscolher={(d) => salvarTarefa(atual.id, { prazo: d })}
          aoMudarHorario={(h) => salvarTarefa(atual.id, { horario: h })} fechar={() => setDataAberta(false)} />
      )}
      {(!atual.concluida) && <div style={{ marginLeft: -3 }}><CampoTempo id={atual.id} /></div>}
      {notas && <p className="t-sm c2" style={{ whiteSpace: "pre-line", display: "-webkit-box", WebkitLineClamp: 8, WebkitBoxOrient: "vertical", overflow: "hidden" }}>{notas}</p>}
      {!atual.mae && !atual.provisoria && <Subtarefas maeId={atual.id} listaId={atual.listaId} />}
    </div>
  );
}

function AbaHoje() {
  const hoje = hojeISO();
  const p = usar((e) => e.prefs);
  const atrasadas = usar((e) => (e.prefs.mostrarAtrasadasNoMenu && !e.prefs.energiaBaixa ? indice(e).atrasadas.filter((t) => !t.mae) : []), mesmaLista);
  const tarefas = usar((e) => indice(e).hoje.filter((t) => !t.mae), mesmaLista);
  const feitas = usar((e) => indice(e).concluidasHoje, mesmaLista);
  const linhas = (ts: Tarefa[]) => ts.map((t) => <LinhaTarefa key={t.id} t={t} compacta />);
  const concluidas = feitas.length > 0 && <Secao titulo="Concluídas" contagem={feitas.length} recolhida>{linhas(feitas)}</Secao>;
  const vazio = !tarefas.length && !atrasadas.length;
  return (
    <>
      <div style={{ padding: "0 var(--e4)" }}><CampoRapidoMenu prazo={hoje} /></div>
      <div className="rolagem-menu">
        {p.mostrarEventosNoMenu && <Eventos dia={hoje} compacto />}
        {atrasadas.length > 0 && (
          <Secao titulo="Em atraso" contagem={atrasadas.length} tom="var(--perigo-texto)" acao={<button className="botao b-fantasma" onClick={adiarAtrasadas}>Adiar p/ hoje</button>}>{linhas(atrasadas)}</Secao>
        )}
        {vazio && concluidas}
        {!tarefas.length ? (vazio && !feitas.length) || !atrasadas.length ? <EstadoVazio Icone={CircleCheck} titulo="Tudo feito por hoje" /> : null
          : !atrasadas.length ? <CartaoLinhas>{linhas(tarefas)}</CartaoLinhas>
          : <Secao titulo="Hoje" contagem={tarefas.length}>{linhas(tarefas)}</Secao>}
        {!vazio && concluidas}
      </div>
    </>
  );
}

function AbaCalendario({ dia, setDia }: { dia: string; setDia: (d: string) => void }) {
  const hoje = hojeISO();
  const porDia = usar((e) => indice(e).porDia);
  const comEvento = usar((e) => (d: string) => eventosDoDia(e, d).length > 0, () => false);
  const ts = (porDia.get(dia) ?? []).filter((t) => !t.mae);
  const nEventos = usar((e) => eventosDoDia(e, dia).length);
  const inicio = somarDias(dia, -deISO(dia).getDay());
  return (
    <>
      <div style={{ display: "flex", alignItems: "center", gap: 2, padding: "0 var(--e4)" }}>
        <button className="icone-botao" style={{ width: 26, height: 26 }} aria-label="Voltar uma semana" onClick={() => setDia(somarDias(dia, -7))}><ChevronLeft size={11} /></button>
        {Array.from({ length: 7 }, (_, i) => somarDias(inicio, i)).map((d) => {
          const sel = d === dia, ehHoje = d === hoje;
          const ocupado = (porDia.get(d)?.length ?? 0) > 0 || comEvento(d);
          return (
            <button key={d} className="dia-semana" onClick={() => setDia(d)} style={{ background: sel ? "var(--acento)" : undefined }}>
              <span className="t-xs p-medio" style={{ color: sel ? "rgba(255,255,255,.85)" : "var(--texto3)" }}>{deISO(d).toLocaleDateString("pt-BR", { weekday: "narrow" }).toUpperCase()}</span>
              <span className="t-md" style={{ fontWeight: sel || ehHoje ? 700 : 500, color: sel ? "#fff" : ehHoje ? "var(--acento)" : "var(--texto)" }}>{Number(d.slice(8))}</span>
              <span style={{ width: 4, height: 4, borderRadius: 9, background: sel ? "#fff" : "var(--acento)", opacity: ocupado ? 1 : 0 }} />
            </button>
          );
        })}
        <button className="icone-botao" style={{ width: 26, height: 26 }} aria-label="Avançar uma semana" onClick={() => setDia(somarDias(dia, 7))}><ChevronRight size={11} /></button>
      </div>
      <div style={{ padding: "0 var(--e4)" }}><CampoRapidoMenu prazo={dia} key={dia} /></div>
      <div className="rolagem-menu">
        <Eventos dia={dia} compacto />
        {!ts.length && !nEventos ? <EstadoVazio Icone={CalendarDays} titulo="Dia livre" /> : ts.length > 0 && <CartaoLinhas>{ts.map((t) => <LinhaTarefa key={t.id} t={t} compacta mostrarData={false} />)}</CartaoLinhas>}
      </div>
    </>
  );
}

function AbaDespejo() {
  const caixa = usar((e) => e.despejo.filter((d) => d.estado === "caixa"), mesmaLista);
  const organizar = () => abrirNaJanela({ tela: "despejo" });
  return (
    <>
      <div style={{ padding: "0 var(--e4)" }}><CampoDespejo compacto /></div>
      <div className="rolagem-menu">
        {!caixa.length ? (
          <EstadoVazio Icone={Brain} titulo="Cabeça leve" descricao="Despeje aqui o que estiver ocupando espaço. Organize depois." />
        ) : (
          <>
            <div style={{ display: "flex", alignItems: "center" }}>
              <span className="t-xs p-semi c3" style={{ flex: 1 }}>{caixa.length} para organizar</span>
              <button className="botao b-fantasma" onClick={organizar}>Organizar na janela</button>
            </div>
            <div className="cartao-linhas fio-curto">
              {[...caixa].reverse().map((i) => (
                <div key={i.id} className="linha-pilha" style={{ padding: "6px 12px", minHeight: 32 }}>
                  <span style={{ width: 5, height: 5, borderRadius: 9, background: "color-mix(in srgb, var(--texto3) 50%, transparent)", flex: "none" }} />
                  <span className="t-sm" style={{ flex: 1, color: i.texto ? "var(--texto)" : "var(--texto3)" }}>{i.texto || "Foto"}</span>
                  <AcoesRapidas id={i.id} tamanho={26} mais={organizar} />
                </div>
              ))}
            </div>
          </>
        )}
      </div>
    </>
  );
}

export function Menu() {
  const hoje = hojeISO();
  const [aba, setAba] = useState<Aba>("hoje");
  const [dia, setDia] = useState(somarDias(hoje, 1));
  const [conta, setConta] = useState(false);
  const email = usar((e) => e.email);
  const avatar = usar((e) => e.avatar);
  useEffect(() => {
    // O app do Mac avisa quando o menu abre: o calendário volta para amanhã e sincroniza.
    const f = () => { setDia(somarDias(hojeISO(), 1)); void puxar(); };
    window.addEventListener("tasker:menuAbriu", f);
    return () => window.removeEventListener("tasker:menuAbriu", f);
  }, []);
  const titulo = { hoje: "Hoje", calendario: "Calendário", despejo: "Despejo" }[aba];
  const ponte = ponteMac();
  const abaBotao = (a: Aba, I: typeof Sun, rotulo: string) => (
    <button className={"aba-pilula" + (aba === a ? " ativa" : "")} title={rotulo} aria-label={rotulo} aria-current={aba === a}
      onClick={() => { if (a === "calendario") setDia(somarDias(hojeISO(), 1)); setAba(a); }}>
      <I size={15} strokeWidth={2.4} />
      {aba === a && <span className="t-sm p-semi">{rotulo}</span>}
    </button>
  );
  return (
    <DetalheNoMenuCtx.Provider value={(t, fechar) => <DetalheNoMenu t={t} fechar={fechar} />}>
      <div className="menu-barra">
        <div style={{ display: "flex", alignItems: "center", gap: "var(--e2)", padding: "16px 16px 12px" }}>
          <h1 className="display d-titulo" style={{ flex: 1 }}>{titulo}</h1>
          <button className="icone-botao" title="Abrir em tela grande" aria-label="Abrir em tela grande" onClick={() => abrirNaJanela({ tela: aba })}><Maximize2 size={14} /></button>
          <span style={{ position: "relative" }}>
            <button className="icone-botao" style={{ width: 30, height: 30, color: "var(--acento)" }} aria-label="Conta" onClick={() => setConta(!conta)}>
              {avatar ? <img src={avatar} alt="" width={28} height={28} style={{ borderRadius: 99 }} /> : <CircleUserRound size={26} strokeWidth={1.8} fill="currentColor" stroke="var(--fundo)" />}
            </button>
            {conta && (
              <div className="dropdown-listas" style={{ position: "absolute", right: 0, top: 34, zIndex: 10, width: 220 }} onMouseLeave={() => setConta(false)}>
                {email && <span className="t-xs c3" style={{ padding: "5px 8px" }}>{email}</span>}
                <button className="opcao-lista t-sm" onClick={() => { setConta(false); void puxar(true); }}>Sincronizar agora</button>
                <button className="opcao-lista t-sm" onClick={() => { setConta(false); abrirNaJanela({ tela: "ajustes" }); }}>Ajustes</button>
                {ponte && <><div style={{ height: 1, background: "var(--borda)", margin: "3px 0" }} /><button className="opcao-lista t-sm" onClick={() => ponte.postMessage({ acao: "encerrar" })}>Encerrar o Tasker</button></>}
              </div>
            )}
          </span>
        </div>
        <div className="conteudo-menu" key={aba}>
          {aba === "hoje" && <AbaHoje />}
          {aba === "calendario" && <AbaCalendario dia={dia} setDia={setDia} />}
          {aba === "despejo" && <AbaDespejo />}
        </div>
        <div style={{ display: "flex", justifyContent: "center", padding: "12px 0" }}>
          <nav className="pilula-menu" aria-label="Abas do menu">
            {abaBotao("hoje", Sun, "Hoje")}
            {abaBotao("calendario", CalendarDays, "Calendário")}
            {abaBotao("despejo", Brain, "Despejo")}
            <span style={{ width: 1, height: 22, background: "var(--borda)", margin: "0 2px", alignSelf: "center" }} />
            <button className="icone-botao" style={{ width: 40, height: 40 }} title="Abrir ajustes" aria-label="Abrir ajustes" onClick={() => abrirNaJanela({ tela: "ajustes" })}><Settings size={15} /></button>
          </nav>
        </div>
      </div>
      <HospedeDeFolhas />
    </DetalheNoMenuCtx.Provider>
  );
}

