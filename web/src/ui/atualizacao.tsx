import { useSyncExternalStore } from "react";
import { Nota } from "./folhas";

// Atualização do app do Mac (UpdateBanner.swift): o atualizador é nativo; a web mostra o aviso
// e os botões, e pede a ele pela ponte.

export interface Atualizacao { atual: string; estado: "nada" | "disponivel" | "instalando" | "falhou" | "procurando" | "emDia" | "erro"; versao: string; erro: string }
let atual: Atualizacao | null = null;
const ouvintes = new Set<() => void>();
(window as unknown as { taskerAtualizacao: (a: Atualizacao) => void }).taskerAtualizacao = (a) => { atual = a; ouvintes.forEach((f) => f()); };

export const useAtualizacao = () => useSyncExternalStore((f) => { ouvintes.add(f); return () => ouvintes.delete(f); }, () => atual);
const pedir = (acao: string) => (window as { webkit?: { messageHandlers?: { tasker?: { postMessage: (m: unknown) => void } } } }).webkit?.messageHandlers?.tasker?.postMessage({ acao });
export const procurarAtualizacao = () => pedir("procurarAtualizacao");

export function AvisoAtualizacao() {
  const a = useAtualizacao();
  if (!a) return null;
  if (a.estado === "disponivel")
    return (
      <Nota texto={`A versão ${a.versao} está pronta para instalar.`}>
        <div style={{ display: "flex", justifyContent: "flex-end" }}><button className="botao b-primario" onClick={() => pedir("atualizar")}>Atualizar agora</button></div>
      </Nota>
    );
  if (a.estado === "instalando")
    return <Nota texto="Atualizando — o Tasker vai reiniciar." />;
  if (a.estado === "falhou")
    return (
      <Nota tom="aviso" texto={`A atualização para ${a.versao} não foi aplicada: o macOS bloqueou a troca do app. Libere o Tasker em Ajustes do Sistema → Privacidade e Segurança → Gerenciamento de Apps e tente de novo.`}>
        <div style={{ display: "flex", gap: "var(--e2)", justifyContent: "flex-end" }}>
          <button className="botao b-superficie" onClick={() => pedir("abrirAjustesDoSistema")}>Abrir Ajustes</button>
          <button className="botao b-primario" onClick={() => { pedir("procurarAtualizacao"); setTimeout(() => pedir("atualizar"), 1500); }}>Tentar de novo</button>
        </div>
      </Nota>
    );
  return null;
}
