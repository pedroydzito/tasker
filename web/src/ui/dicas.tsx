import { useEffect, useRef, useState } from "react";
import { Lightbulb, X } from "lucide-react";
import { ler, usar } from "../dados/armazem";
import { mudarPrefs } from "../dados/acoes";
import type { Rota } from "./rota";

// Dica de primeira vez (design system §8.38): um balão embaixo da tela, uma vez por CONTA (a marca
// sobe com as preferências e vale em todo aparelho), 900 ms depois de a tela abrir, some em 7 s,
// no X ou jogada para o lado. Uma por vez; a seguinte espera a próxima tela.

interface Dica { id: string; texto: string; vale: (r: Rota, celular: boolean) => boolean }
const DICAS: Dica[] = [
  { id: "segurar-tarefa", texto: "Segure uma tarefa para concluir, mudar a data, pôr etiquetas ou excluir.", vale: (r, c) => c && ["hoje", "amanha", "todas", "lista"].includes(r.tela) },
  { id: "botao-direito", texto: "Clique com o botão direito numa tarefa para mudar a data, pôr etiquetas ou excluir.", vale: (r, c) => !c && ["hoje", "amanha", "todas", "lista"].includes(r.tela) },
  { id: "arrastar-lista", texto: "Arraste uma tarefa até uma lista da barra lateral para mudá-la de lista.", vale: (r, c) => !c && r.tela === "lista" },
  { id: "criacao-rapida", texto: "Escreva “amanhã”, “sexta”, “~lista” ou “#etiqueta” no campo de nova tarefa — o Tasker entende.", vale: (r) => r.tela === "hoje" },
  { id: "busca", texto: "⌘K busca em tarefas, notas, despejo e agenda ao mesmo tempo.", vale: (r, c) => !c && r.tela === "todas" },
  { id: "despejo", texto: "Despeje tudo o que ocupa a cabeça. Depois, “Organizar 3” decide três de cada vez.", vale: (r) => r.tela === "despejo" },
  { id: "nota-colchetes", texto: "Numa nota, comece a linha com [ ] e ela pode virar tarefa num toque.", vale: (r) => r.tela === "notas" || r.tela === "nota" },
  { id: "pilula-arrastar", texto: "Deslize o dedo pela barra de baixo para trocar de tela sem soltar.", vale: (r, c) => c && r.tela === "calendario" },
];

export function DicaDePrimeiraVez({ rota, celular }: { rota: Rota; celular: boolean }) {
  const modo = usar((e) => e.modo);
  const [dica, setDica] = useState<Dica | null>(null);
  const [saindo, setSaindo] = useState<number | null>(null);
  const [dx, setDx] = useState(0);
  const toque = useRef<{ x: number; y: number; decidido: boolean; lado: boolean } | null>(null);

  useEffect(() => {
    if (modo !== "conta" && modo !== "local") return;
    const t = setTimeout(() => {
      const vistas = ler().prefs.dicasVistas ?? [];
      const d = DICAS.find((x) => !vistas.includes(x.id) && x.vale(rota, celular));
      if (!d) return;
      setDx(0); setSaindo(null); setDica(d);
      // Conta como vista assim que aparece.
      mudarPrefs((p) => ({ dicasVistas: [...(p.dicasVistas ?? []), d.id] }));
    }, 900);
    return () => clearTimeout(t);
  }, [rota, modo]);
  useEffect(() => {
    if (!dica) return;
    const t = setTimeout(() => sair(1), 7000);
    return () => clearTimeout(t);
  }, [dica]);
  const sair = (lado: number) => { setSaindo(lado); setTimeout(() => setDica(null), 280); };
  if (!dica) return null;
  return (
    <div className="vaga-dica">
      <div className="aviso-abrindo">
        <div className="cartao dica" role="status"
          style={{ transform: saindo !== null ? `translateX(${saindo * innerWidth}px)` : `translateX(${dx}px)`, opacity: saindo !== null ? 0 : 1 - Math.abs(dx) / 240, transition: toque.current?.lado ? "none" : undefined }}
          onTouchStart={(e) => { const t = e.touches[0]; toque.current = { x: t.clientX, y: t.clientY, decidido: false, lado: false }; }}
          onTouchMove={(e) => {
            const g = toque.current, t = e.touches[0];
            if (!g) return;
            const ddx = t.clientX - g.x, ddy = t.clientY - g.y;
            if (!g.decidido) { if (Math.hypot(ddx, ddy) < 6) return; g.decidido = true; g.lado = Math.abs(ddx) > Math.abs(ddy); }
            if (g.lado) setDx(ddx);
          }}
          onTouchEnd={() => { const g = toque.current; toque.current = null; if (g?.lado && Math.abs(dx) > 80) sair(Math.sign(dx)); else setDx(0); }}>
          <Lightbulb size={16} color="var(--acento)" style={{ marginTop: 2, flex: "none" }} />
          <span className="t-sm" style={{ flex: 1, lineHeight: 1.5 }}>{dica.texto}</span>
          <button className="icone-botao alvo-toque" style={{ position: "absolute", right: 6, top: 6, width: 24, height: 24 }} aria-label="Fechar dica" onClick={() => sair(1)}><X size={14} /></button>
        </div>
      </div>
    </div>
  );
}
