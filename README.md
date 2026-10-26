# Tasker

App nativo para macOS (Swift + SwiftUI) que vive na **barra de menu** e mostra suas **tarefas do Google Tasks** junto com os **eventos do dia do Google Calendar**. Pega o melhor do KiteTasks (popover, eventos do dia, criação rápida) com algumas ideias do TickTick, num visual próprio e mais limpo.

## O que ele faz

- **Ícone na barra de menu com contador**: ícone de tarefa com um selo mostrando quantas faltam para hoje e se atualiza na hora quando você cria ou conclui uma tarefa. Dá para trocar por "ícone + número ao lado", e decidir se as atrasadas entram na conta.
- **Popover "Hoje"**: eventos do dia (recolhíveis), tarefas em atraso com botão **Adiar** (manda tudo para hoje), tarefas de hoje e um campo para adicionar.
- **Janela principal**: Hoje, Amanhã, Próximas (14 dias), Calendário (mês + agenda do dia), Todas (por data ou por lista), Concluídas, cada lista do Google e as etiquetas. Clicar numa tarefa abre o painel de detalhes à direita.
- **Listas com a sua cara**: ícone (biblioteca de ícones), foto ou inicial, e cor (com código hex). Crie, renomeie, exclua e reordene as listas arrastando. Listas criadas no Tasker aparecem também no Google Tasks (só o ícone e a cor ficam no app).
- **Usar sem conta**: dá para usar o Tasker sem Google — tudo fica só neste Mac, sem servidor. **Exportar/Importar** (Ajustes → Dados) leva listas, tarefas e etiquetas para outro Mac ou para a conta Google depois.
- **Tema**: Sistema, Claro ou Escuro (o menu não escurece só porque a barra está escura).
- **Etiquetas locais**: ficam só no Tasker e não vão para o Google Tasks. As **listas** continuam sendo as do Google.
- **Criação rápida com linguagem natural**: `Ligar pro cliente amanhã ~trabalho #urgente`
  - datas: `hoje`, `amanhã`, `depois de amanhã`, `segunda` … `domingo`, `30/10`, `sem data`
  - `~lista` escolhe a lista do Google; `#etiqueta` adiciona (ou cria) uma etiqueta local
- **⌥Espaço** abre a criação rápida de qualquer lugar, mesmo com o app em segundo plano.
- **Sincronização contínua**: a cada 30 s por padrão (dá para mudar), de forma incremental; também ao abrir o popover, ao acordar o Mac e na virada do dia. As alterações aparecem na hora no app e são enviadas ao Google em seguida. Um cache local faz o app abrir na hora, mesmo sem internet.
- Opção **Abrir ao iniciar o Mac**.

## 1. Conectar o Google (opcional)

Quer só usar no Mac? Escolha **Usar sem conta** na primeira abertura e pule esta parte.

Para sincronizar com o Google Tasks e a Agenda, o Tasker precisa de uma credencial OAuth sua (uma vez só). Na tela de boas-vindas (ou em Ajustes → Conta), cada passo tem um link direto:

1. **Ativar as APIs Tasks e Calendar**: o link cria o projeto e liga as duas APIs de uma vez.
2. **Configurar a tela de consentimento**: tipo **Externo**, seu e-mail como usuário de teste e **Publicar app** (em modo "Teste" o Google desconecta a cada 7 dias). Como o app não é verificado, no login aparece "O Google não verificou este app" → **Avançado → Acessar Tasker**.
3. **Criar a credencial "App para computador"** e clicar em **Baixar JSON**.
4. **Soltar o JSON na área indicada**: o Tasker lê o ID e o secret sozinho. Depois é só **Entrar com Google**.

As credenciais e os tokens ficam em `~/Library/Application Support/Tasker/secrets.json`, legível só pelo seu usuário. Elas não são embutidas no app publicado, porque os releases deste repositório são públicos.

## 2. Instalar

1. Baixe o `Tasker.dmg` do [último release](https://github.com/pedroydzito/tasker/releases/latest), abra e arraste o **Tasker** para **Aplicativos**. (O `Tasker.zip` do release é o que o atualizador automático usa.)
2. Como o app não é assinado com conta de desenvolvedor Apple, rode isto uma vez no Terminal:
   ```bash
   xattr -cr /Applications/Tasker.app
   ```
3. Abra o Tasker e permita as notificações (é por elas que chegam os avisos de atualização).

> O KiteTasks também usa **⌥Espaço**. Se os dois estiverem abertos, desative o atalho em um deles.

## Atualizações automáticas

Cada alteração enviada ao GitHub gera um novo release (`v0.1.<número>`) pelo GitHub Actions. O Tasker verifica a cada 30 minutos (ou em **Ajustes → Procurar atualizações**) e, quando encontra uma versão nova:

- mostra uma **notificação** com o botão **Atualizar** e um aviso no topo do popover;
- ao clicar, baixa a nova versão, substitui o app, **reinicia e abre já atualizado**.

Se o macOS bloquear a troca do app (proteção **Gerenciamento de Apps**, comum em apps sem assinatura da Apple), o Tasker avisa ao reabrir. Libere em **Ajustes do Sistema → Privacidade e Segurança → Gerenciamento de Apps → Tasker** e clique em **Tentar de novo**, ou use **Instalar manualmente**. O registro de cada tentativa fica em `~/Library/Logs/Tasker-update.log`.

Seus dados não se perdem: login, etiquetas e preferências ficam em `~/Library/Application Support/Tasker` e nas preferências do usuário, fora do app.

## Compilar localmente (opcional)

Precisa de macOS 15 ou mais novo e do Xcode (ou das Command Line Tools: `xcode-select --install`).

```bash
make install      # compila, copia para /Applications e abre
```

Builds locais saem com número de build 0, e o atualizador automático não os substitui (para não sobrescrever o que você está testando).

## Estrutura do código

```
Sources/Tasker/
  App/        entrada do app (MenuBarExtra + janela), AppDelegate, ícone
  Google/     OAuth (loopback + PKCE), Keychain, clientes das APIs Tasks e Calendar
  Store/      TaskStore (estado + sync), modelos, preferências, etiquetas, parser da criação rápida
  QuickAdd/   atalho global (Carbon) e painel flutuante
  Views/      popover, janela principal, sidebar, telas, componentes
```

## Sobre a engenharia reversa (REA)

O [REA](https://github.com/morluto/rea) é um servidor MCP que analisa binários localmente, usando Hopper, Ghidra ou IDA. Este projeto não precisou dele: tudo o que o KiteTasks mostra vem das APIs públicas do Google Tasks e do Google Calendar, então o Tasker foi feito a partir do comportamento visível do app. Se no futuro quiser entender algum detalhe específico do KiteTasks, rode `npx rea-agents setup` no seu Mac e aponte para `/Applications/KiteTasks.app`.

## Ideias para depois

- Subtarefas criadas pelo app e arrastar para reordenar
- Lembretes e notificações locais
- Prioridade (local, como as etiquetas)
- Widget na Central de Notificações
