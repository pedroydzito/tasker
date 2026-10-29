// Novidades de cada versão, na língua de quem usa (operação: versionamento). A primeira da lista
// é sempre a do package.json — um teste cobra. Z: ajuste (até 99); Y: mudança grande (até 9).

export interface Novidade { versao: string; data: string; itens: string[] }

export const NOVIDADES: Novidade[] = [
  {
    versao: "1.0.0",
    data: "2026-10-29",
    itens: [
      "O Tasker agora existe na web e no celular, com a mesma cara do app do Mac, e funciona sem internet.",
      "Arquivos anexados às tarefas.",
      "Campo de nova tarefa com a lista e a data à mão enquanto você digita.",
      "Clique com o botão direito (ou segure o dedo) numa tarefa para mudar a data, pôr etiquetas ou excluir.",
      "Arraste uma tarefa até uma lista da barra lateral para mudá-la de lista.",
      "No celular: barra de baixo que dá para deslizar com o dedo, puxar para atualizar e dicas na primeira vez.",
      "O tema e as suas escolhas de tela viajam com a conta para todos os aparelhos.",
      "Correções de design e experiência do usuário.",
    ],
  },
];
