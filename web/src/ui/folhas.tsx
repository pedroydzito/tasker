import { useEffect, useState, useSyncExternalStore, type ReactNode } from "react";
import {
  Archive, Banknote, Bike, Book, Bookmark, Brain, Briefcase, BriefcaseMedical, Building2, Bus, Calendar, Camera, Car, ChartColumn, ChartPie, ChevronUp,
  CircleDollarSign, Clock, AlarmClock, Cloud, Code, Coffee, CreditCard, Dumbbell, FileText, Film, Flag, Flame, Folder, Gamepad2, Gift, Globe,
  GraduationCap, Hammer, Headphones, Heart, House, Image, Inbox, Laptop, LayoutGrid, Leaf, Library, Lightbulb, Link, List, ListChecks, Lock, Mail,
  Map, MapPin, Megaphone, MessageCircle, Mic, Monitor, Moon, Music, Palette, Paperclip, PawPrint, Pencil, PencilRuler, PenTool, PersonStanding, Phone,
  Plane, Plus, Scissors, Search, Send, Settings, ShoppingBag, ShoppingCart, Smartphone, Sparkles, Star, Stethoscope, Store, Sun, Tag, Target,
  Terminal, TrendingUp, TreePine, Tv, User, Users, UsersRound, Utensils, Video, WandSparkles, Wine, Wrench, X, Zap, type LucideIcon,
} from "lucide-react";
import { usar } from "../dados/armazem";
import { criarEtiqueta, criarLista, editarEtiqueta, excluirEtiqueta, excluirLista, mudarPrefs, renomearLista } from "../dados/acoes";
import { corDaLista, iconeDaLista, nomeDaLista } from "../dados/consultas";
import { PALETA, normalizarBusca } from "../dados/util";
import { irPara } from "./rota";

// Folhas (Folha.swift): um componente para todos os diálogos. Véu, caixa centrada com raio de
// cartão, cabeçalho com título display e X, corpo rolável. Esc e clique no véu fecham.

interface Atual {
  id: number;
  titulo: string;
  descricao?: string;
  largura: number;
  conteudo: ReactNode;
}
let atual: Atual | null = null;
let seq = 0;
const ouvintes = new Set<() => void>();
const emitir = () => ouvintes.forEach((f) => f());

export const folhas = {
  abrir(titulo: string, conteudo: ReactNode, o: { largura?: number; descricao?: string } = {}) {
    atual = { id: ++seq, titulo, conteudo, largura: o.largura ?? 400, descricao: o.descricao };
    emitir();
  },
  fechar() {
    atual = null;
    emitir();
  },
  /** Confirmação padrão para tudo que remove algo. */
  confirmar(titulo: string, mensagem: string, acao: () => void, botao = "Excluir") {
    folhas.abrir(titulo, <Confirmacao mensagem={mensagem} botao={botao} acao={acao} />, { largura: 360 });
  },
};

export function RodapeFolha({ children }: { children: ReactNode }) {
  return (
    <div style={{ display: "flex", flexDirection: "column", gap: "var(--e4)", paddingTop: "var(--e2)" }}>
      <div style={{ height: 1, background: "var(--borda)", margin: "0 calc(-1 * var(--e5))" }} />
      <div style={{ display: "flex", alignItems: "center", gap: "var(--e2)" }}>{children}</div>
    </div>
  );
}

function Confirmacao({ mensagem, botao, acao }: { mensagem: string; botao: string; acao: () => void }) {
  const ok = () => { folhas.fechar(); acao(); };
  useEffect(() => {
    const k = (e: KeyboardEvent) => e.key === "Enter" && ok();
    window.addEventListener("keydown", k);
    return () => window.removeEventListener("keydown", k);
  });
  return (
    <div style={{ display: "flex", flexDirection: "column", gap: "var(--e4)" }}>
      <p className="t-sm c2">{mensagem}</p>
      <RodapeFolha>
        <span style={{ flex: 1 }} />
        <button className="botao b-superficie" onClick={folhas.fechar}>Cancelar</button>
        <button className="botao b-perigo" autoFocus onClick={ok}>{botao}</button>
      </RodapeFolha>
    </div>
  );
}

export function HospedeDeFolhas() {
  const a = useSyncExternalStore((f) => { ouvintes.add(f); return () => ouvintes.delete(f); }, () => atual);
  useEffect(() => {
    if (!a) return;
    const k = (e: KeyboardEvent) => e.key === "Escape" && folhas.fechar();
    window.addEventListener("keydown", k);
    return () => window.removeEventListener("keydown", k);
  }, [a]);
  if (!a) return null;
  return (
    <>
      <div className="veu-modal" onClick={folhas.fechar} />
      <div className="folha" role="dialog" aria-label={a.titulo} key={a.id} style={{ ["--largura" as string]: a.largura + "px" }}>
        <div className="folha-cabecalho">
          <div style={{ flex: 1, display: "flex", flexDirection: "column", gap: "var(--e1)" }}>
            <h2 className="display d-lg">{a.titulo}</h2>
            {a.descricao && <span className="t-sm c3">{a.descricao}</span>}
          </div>
          <button className="icone-botao" style={{ width: 28, height: 28, marginTop: -2, marginRight: -4 }} aria-label="Fechar" onClick={folhas.fechar}><X size={12} /></button>
        </div>
        <div className="folha-corpo">{a.conteudo}</div>
      </div>
    </>
  );
}

// MARK: Ícones das listas (Palette.icones, com as mesmas palavras de busca)

export const ICONES: [string, LucideIcon, string][] = [
  ["person", User, "pessoa cliente perfil"], ["person.2", Users, "pessoas dupla equipe"], ["person.3", UsersRound, "grupo time equipe"],
  ["briefcase", Briefcase, "trabalho maleta emprego"], ["building.2", Building2, "empresa prédio escritório"], ["house", House, "casa lar"],
  ["storefront", Store, "loja comércio"], ["cart", ShoppingCart, "compras mercado carrinho"], ["bag", ShoppingBag, "sacola compras"],
  ["paintbrush.pointed", PenTool, "design pincel arte"], ["paintpalette", Palette, "arte paleta cores"], ["pencil.and.ruler", PencilRuler, "projeto régua"],
  ["pencil", Pencil, "lápis escrever editar"], ["scissors", Scissors, "tesoura corte"], ["camera", Camera, "câmera foto"], ["photo", Image, "imagem foto"],
  ["film", Film, "filme cinema vídeo"], ["video", Video, "vídeo gravação"], ["music.note", Music, "música som"], ["headphones", Headphones, "fone podcast"],
  ["mic", Mic, "microfone áudio"], ["gamecontroller", Gamepad2, "jogo game"], ["tv", Tv, "tv série"], ["book", Book, "livro leitura"],
  ["books.vertical", Library, "livros estudo biblioteca"], ["graduationcap", GraduationCap, "estudo faculdade curso"], ["lightbulb", Lightbulb, "ideia lâmpada"],
  ["brain", Brain, "mente cérebro"], ["heart", Heart, "coração amor saúde"], ["star", Star, "estrela favorito"], ["flame", Flame, "fogo urgente"],
  ["bolt", Zap, "raio energia rápido"], ["leaf", Leaf, "folha natureza"], ["tree", TreePine, "árvore natureza"], ["sun.max", Sun, "sol dia"],
  ["moon", Moon, "lua noite"], ["cloud", Cloud, "nuvem"], ["figure.run", PersonStanding, "corrida exercício"], ["dumbbell", Dumbbell, "academia treino"],
  ["bicycle", Bike, "bicicleta"], ["fork.knife", Utensils, "comida restaurante"], ["cup.and.saucer", Coffee, "café"], ["wineglass", Wine, "vinho festa"],
  ["airplane", Plane, "viagem avião"], ["car", Car, "carro"], ["bus", Bus, "ônibus transporte"], ["map", Map, "mapa"],
  ["mappin.and.ellipse", MapPin, "lugar local"], ["globe.americas", Globe, "mundo internet"], ["creditcard", CreditCard, "cartão pagamento"],
  ["banknote", Banknote, "dinheiro nota"], ["dollarsign.circle", CircleDollarSign, "dinheiro finanças"], ["chart.bar", ChartColumn, "gráfico métricas"],
  ["chart.line.uptrend.xyaxis", TrendingUp, "crescimento vendas"], ["chart.pie", ChartPie, "gráfico pizza"], ["doc.text", FileText, "documento texto"],
  ["folder", Folder, "pasta arquivos"], ["tray", Inbox, "caixa entrada"], ["archivebox", Archive, "arquivo caixa"], ["paperclip", Paperclip, "anexo clipe"],
  ["link", Link, "link"], ["laptopcomputer", Laptop, "notebook computador"], ["desktopcomputer", Monitor, "computador"], ["iphone", Smartphone, "celular telefone"],
  ["chevron.left.forwardslash.chevron.right", Code, "código programação dev"], ["terminal", Terminal, "terminal dev"],
  ["megaphone", Megaphone, "marketing anúncio"], ["bubble.left", MessageCircle, "conversa mensagem"], ["phone", Phone, "telefone ligação"],
  ["envelope", Mail, "email carta"], ["paperplane", Send, "enviar"], ["calendar", Calendar, "calendário agenda"], ["clock", Clock, "relógio hora"],
  ["alarm", AlarmClock, "alarme lembrete"], ["flag", Flag, "bandeira meta"], ["bookmark", Bookmark, "marcador"], ["tag", Tag, "etiqueta"],
  ["target", Target, "alvo meta objetivo"], ["checklist", ListChecks, "lista tarefas"], ["list.bullet", List, "lista"], ["square.grid.2x2", LayoutGrid, "grade apps"],
  ["sparkles", Sparkles, "brilho mágica"], ["wand.and.stars", WandSparkles, "mágica"], ["gift", Gift, "presente aniversário"], ["pawprint", PawPrint, "pet animal"],
  ["stethoscope", Stethoscope, "médico saúde"], ["cross.case", BriefcaseMedical, "saúde remédio"], ["hammer", Hammer, "ferramenta obra"],
  ["wrench.and.screwdriver", Wrench, "manutenção conserto"], ["gearshape", Settings, "configuração"], ["lock", Lock, "senha segurança"],
];
export const iconePorNome = (nome: string | null | undefined): LucideIcon | null => (nome ? ICONES.find(([n]) => n === nome.replace(/\.fill$/, ""))?.[1] ?? null : null);

function SeletorDeIcone({ selecionado, cor, aoEscolher }: { selecionado: string | null; cor: string; aoEscolher: (n: string) => void }) {
  const [busca, setBusca] = useState("");
  const termo = normalizarBusca(busca).trim();
  const resultados = termo ? ICONES.filter(([n, , b]) => normalizarBusca(b + " " + n).includes(termo)) : ICONES;
  return (
    <div style={{ display: "flex", flexDirection: "column", gap: "var(--e2)" }}>
      <div className="campo-inline"><Search size={12} className="c3" /><input placeholder="Buscar: casa, trabalho, dinheiro…" value={busca} onChange={(e) => setBusca(e.target.value)} /></div>
      <div style={{ height: 172, overflow: "auto", display: "grid", gridTemplateColumns: "repeat(9, 1fr)", gap: 6, padding: 2, alignContent: "start" }}>
        {resultados.map(([n, I]) => (
          <button key={n} title={n} className="afunda" onClick={() => aoEscolher(n)}
            style={{ height: 36, borderRadius: "var(--raio-m)", display: "inline-flex", alignItems: "center", justifyContent: "center", background: selecionado === n ? cor : "var(--superficie2)", color: selecionado === n ? "#fff" : "var(--texto2)" }}>
            <I size={15} strokeWidth={1.8} />
          </button>
        ))}
        {!resultados.length && <span className="t-xs c3" style={{ gridColumn: "1 / -1", textAlign: "center", paddingTop: 70 }}>Nenhum ícone para “{busca}”</span>}
      </div>
    </div>
  );
}

function AmostrasDeCor({ selecao, aoEscolher }: { selecao: string; aoEscolher: (c: string) => void }) {
  const [personalizada, setPersonalizada] = useState(false);
  return (
    <div style={{ display: "flex", flexDirection: "column", gap: "var(--e3)" }}>
      <div style={{ display: "flex", gap: 6, flexWrap: "wrap", alignItems: "center" }}>
        {PALETA.map((c) => (
          <button key={c} className="afunda" aria-label={c} onClick={() => aoEscolher(c)} style={{ padding: 4, borderRadius: 99, boxShadow: c.toUpperCase() === selecao.toUpperCase() ? `inset 0 0 0 2px ${c}` : undefined }}>
            <span style={{ display: "block", width: 22, height: 22, borderRadius: 99, background: c, border: "4px solid var(--superficie)" }} />
          </button>
        ))}
        <button className="afunda" title="Outra cor" onClick={() => setPersonalizada(!personalizada)} style={{ width: 26, height: 26, borderRadius: 99, background: "var(--superficie2)", color: "var(--texto2)", display: "inline-flex", alignItems: "center", justifyContent: "center" }}>
          {personalizada ? <ChevronUp size={11} strokeWidth={3} /> : <Plus size={11} strokeWidth={3} />}
        </button>
      </div>
      {personalizada && (
        <div className="entrar" style={{ display: "flex", gap: "var(--e3)", alignItems: "center" }}>
          <input type="color" value={selecao} onChange={(e) => aoEscolher(e.target.value.toUpperCase())} style={{ width: 40, height: 36, border: "1px solid var(--borda)", borderRadius: "var(--raio-m)", padding: 0, background: "none" }} />
          <div className="campo-inline" style={{ height: 36, flex: 1 }}>
            <span className="t-md p-medio c3">#</span>
            <input className="numeros" defaultValue={selecao.replace("#", "")} maxLength={7} onChange={(e) => { const v = e.target.value.replace("#", "").trim(); if (/^[0-9a-f]{6}$/i.test(v)) aoEscolher("#" + v.toUpperCase()); }} />
          </div>
        </div>
      )}
    </div>
  );
}

function Previa({ nome, icone, cor, tamanho = 56 }: { nome: string; icone: string | null; cor: string; tamanho?: number }) {
  const I = iconePorNome(icone);
  const limpo = nome.replace(/^[^\p{L}\p{N}]+/u, "").trim() || nome;
  return (
    <span style={{ padding: 4, borderRadius: tamanho * 0.3 + 4, border: `2px solid ${cor}`, display: "inline-flex", flex: "none" }}>
      <span style={{ width: tamanho, height: tamanho, borderRadius: tamanho * 0.3, background: `color-mix(in srgb, ${cor} 16%, transparent)`, color: cor, display: "inline-flex", alignItems: "center", justifyContent: "center", fontFamily: "ui-rounded, system-ui", fontWeight: 700, fontSize: tamanho * 0.46 }}>
        {I ? <I size={tamanho * 0.48} strokeWidth={1.8} /> : (limpo[0] ?? "").toUpperCase()}
      </span>
    </span>
  );
}

/** Folha "Nova lista": nome, ícone e cor. */
export function NovaLista() {
  const modo = usar((e) => e.modo);
  const [nome, setNome] = useState("");
  const [icone, setIcone] = useState<string | null>(null);
  const [cor, setCor] = useState(PALETA[5]);
  const criar = () => {
    if (!nome.trim()) return;
    const id = criarLista(nome.trim(), { icone, cor });
    folhas.fechar();
    if (id) irPara({ tela: "lista", id });
  };
  return (
    <div style={{ display: "flex", flexDirection: "column", gap: "var(--e5)" }}>
      <label style={{ display: "flex", flexDirection: "column", gap: 6 }}><span className="rotulo">Nome</span>
        <input className="campo" autoFocus placeholder="Ex.: Clientes" value={nome} onChange={(e) => setNome(e.target.value)} onKeyDown={(e) => e.key === "Enter" && criar()} /></label>
      <div style={{ display: "flex", flexDirection: "column", gap: "var(--e2)" }}><span className="rotulo">Ícone</span><SeletorDeIcone selecionado={icone} cor={cor} aoEscolher={setIcone} /></div>
      <div style={{ display: "flex", flexDirection: "column", gap: "var(--e2)" }}><span className="rotulo">Cor</span><AmostrasDeCor selecao={cor} aoEscolher={setCor} /></div>
      {modo === "conta" && <Nota texto="A lista também é criada no Google Tasks. O ícone e a cor ficam só no Tasker." />}
      <RodapeFolha>
        <span style={{ flex: 1 }} />
        <button className="botao b-superficie" onClick={folhas.fechar}>Cancelar</button>
        <button className="botao b-primario" disabled={!nome.trim()} onClick={criar}>Criar lista</button>
      </RodapeFolha>
    </div>
  );
}

/** Folha "Personalizar lista": nome, ícone (ou inicial) e cor. Só salva ao clicar em "Salvar". */
export function EditorDeLista({ listaId }: { listaId: string }) {
  const titulo = usar((e) => e.listas.find((l) => l.id === listaId)?.titulo ?? "");
  const fixa = usar((e) => e.listaFixa === listaId);
  const nomeAtual = usar((e) => nomeDaLista(e, listaId));
  const [nome, setNome] = useState(titulo);
  const [icone, setIcone] = useState<string | null>(usar((e) => iconeDaLista(e, listaId)));
  const [modo, setModo] = useState<"icone" | "inicial">(icone ? "icone" : "inicial");
  const [cor, setCor] = useState(usar((e) => corDaLista(e, listaId)));
  const salvar = () => {
    if (nome.trim() && nome.trim() !== titulo) renomearLista(listaId, nome.trim());
    mudarPrefs((p) => ({ coresListas: { ...p.coresListas, [listaId]: cor }, iconesListas: { ...p.iconesListas, [listaId]: modo === "icone" && icone ? icone : "" } }));
    folhas.fechar();
  };
  return (
    <div style={{ display: "flex", flexDirection: "column", gap: "var(--e5)" }}>
      <div style={{ display: "flex", gap: "var(--e4)", alignItems: "center" }}>
        <Previa nome={nome} icone={modo === "icone" ? icone : null} cor={cor} />
        <label style={{ display: "flex", flexDirection: "column", gap: 6, flex: 1 }}><span className="rotulo">Nome</span>
          <input className="campo" placeholder="Nome da lista" value={nome} onChange={(e) => setNome(e.target.value)} /></label>
      </div>
      <div style={{ display: "flex", flexDirection: "column", gap: "var(--e3)" }}>
        <div style={{ display: "flex", alignItems: "center" }}>
          <span className="rotulo" style={{ flex: 1 }}>Ícone</span>
          <div className="segmentado">
            <button aria-pressed={modo === "icone"} onClick={() => setModo("icone")}>Ícone</button>
            <button aria-pressed={modo === "inicial"} onClick={() => setModo("inicial")}>Inicial</button>
          </div>
        </div>
        {modo === "icone" ? <SeletorDeIcone selecionado={icone} cor={cor} aoEscolher={setIcone} /> : <span className="t-xs c3">Mostra a primeira letra do nome sobre a cor da lista.</span>}
      </div>
      <div style={{ display: "flex", flexDirection: "column", gap: "var(--e2)" }}><span className="rotulo">Cor</span><AmostrasDeCor selecao={cor} aoEscolher={setCor} /></div>
      <RodapeFolha>
        {!fixa && (
          <button className="botao b-fantasma" onClick={() => folhas.confirmar("Excluir lista", `“${nomeAtual}” e as tarefas dela serão excluídas, também no Google Tasks. Dá para desfazer logo depois.`, () => { excluirLista(listaId); irPara({ tela: "hoje" }); })}>Excluir lista</button>
        )}
        <span style={{ flex: 1 }} />
        <button className="botao b-superficie" onClick={folhas.fechar}>Cancelar</button>
        <button className="botao b-primario" onClick={salvar}>Salvar</button>
      </RodapeFolha>
    </div>
  );
}

/** Folha "Nova etiqueta". */
export function CriadorDeEtiqueta({ aoCriar }: { aoCriar?: (id: string) => void }) {
  const [nome, setNome] = useState("");
  const [cor, setCor] = useState(PALETA[5]);
  const criar = () => {
    const limpo = nome.trim().replace(/^#/, "");
    if (!limpo) return;
    const g = criarEtiqueta(limpo, cor);
    folhas.fechar();
    aoCriar?.(g.id);
  };
  return (
    <div style={{ display: "flex", flexDirection: "column", gap: "var(--e4)" }}>
      <label style={{ display: "flex", flexDirection: "column", gap: 6 }}><span className="rotulo">Nome</span>
        <input className="campo" autoFocus placeholder="Ex.: urgente" value={nome} onChange={(e) => setNome(e.target.value)} onKeyDown={(e) => e.key === "Enter" && criar()} /></label>
      <div style={{ display: "flex", flexDirection: "column", gap: 6 }}><span className="rotulo">Cor</span><AmostrasDeCor selecao={cor} aoEscolher={setCor} /></div>
      <Nota texto="Etiquetas ficam só no Tasker — não vão para o Google Tasks." />
      <RodapeFolha>
        <span style={{ flex: 1 }} />
        <button className="botao b-superficie" onClick={folhas.fechar}>Cancelar</button>
        <button className="botao b-primario" disabled={!nome.trim()} onClick={criar}>Criar etiqueta</button>
      </RodapeFolha>
    </div>
  );
}

/** Nota informativa (Nota do design system). */
export function Nota({ texto, tom = "info", children }: { texto: string; tom?: "info" | "aviso" | "erro"; children?: ReactNode }) {
  const cores = { info: ["var(--superficie2)", "var(--texto2)"], aviso: ["var(--aviso-tenue, #9a5b121a)", "var(--aviso)"], erro: ["var(--perigo-tenue)", "var(--perigo-texto)"] }[tom];
  return (
    <div style={{ padding: "var(--e3)", borderRadius: "var(--raio-m)", background: cores[0], display: "flex", flexDirection: "column", gap: "var(--e2)" }}>
      <span className="t-sm" style={{ color: cores[1] }}>{texto}</span>
      {children}
    </div>
  );
}

/** Folha "Editar etiqueta": nome e cor; excluir tira a etiqueta de todas as tarefas. */
export function EditorDeEtiqueta({ id }: { id: string }) {
  const g = usar((e) => e.etiquetas.find((x) => x.id === id) ?? null);
  const [nome, setNome] = useState(g?.nome ?? "");
  const [cor, setCor] = useState(g?.cor ?? PALETA[5]);
  if (!g) return null;
  return (
    <div style={{ display: "flex", flexDirection: "column", gap: "var(--e4)" }}>
      <label style={{ display: "flex", flexDirection: "column", gap: 6 }}><span className="rotulo">Nome</span>
        <input className="campo" placeholder="Nome" value={nome} onChange={(e) => setNome(e.target.value)} /></label>
      <div style={{ display: "flex", flexDirection: "column", gap: "var(--e2)" }}><span className="rotulo">Cor</span><AmostrasDeCor selecao={cor} aoEscolher={setCor} /></div>
      <RodapeFolha>
        <button className="botao b-fantasma" onClick={() => folhas.confirmar("Excluir etiqueta", `A etiqueta “${g.nome}” sai de todas as tarefas.`, () => { irPara({ tela: "hoje" }); excluirEtiqueta(id); })}>Excluir etiqueta</button>
        <span style={{ flex: 1 }} />
        <button className="botao b-superficie" onClick={folhas.fechar}>Cancelar</button>
        <button className="botao b-primario" onClick={() => { editarEtiqueta(id, { nome: nome.trim() || g.nome, cor }); folhas.fechar(); }}>Salvar</button>
      </RodapeFolha>
    </div>
  );
}
