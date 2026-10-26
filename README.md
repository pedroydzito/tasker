# Tasker

App nativo para macOS (Swift + SwiftUI) que vive na **barra de menu** e mostra suas **tarefas do Google Tasks** junto com os **eventos do dia do Google Calendar**. Pega o melhor do KiteTasks (popover, eventos do dia, criação rápida) com algumas ideias do TickTick, num visual próprio e mais limpo.

## O que ele faz

- **Ícone na barra de menu com contador**: mostra quantas tarefas faltam para hoje e se atualiza na hora quando você cria ou conclui uma tarefa. Dá para escolher entre "ícone + número" e "número no quadrado", e decidir se as atrasadas entram na conta.
- **Popover "Hoje"**: eventos do dia (recolhíveis), tarefas em atraso com botão **Adiar** (manda tudo para hoje), tarefas de hoje e um campo para adicionar.
- **Janela principal**: Hoje, Amanhã, Próximas (14 dias), Calendário (mês + agenda do dia), Todas (por data ou por lista), Concluídas, cada lista do Google e as etiquetas. Clicar numa tarefa abre o painel de detalhes à direita.
- **Etiquetas locais**: ficam só no Tasker e não vão para o Google Tasks. As **listas** continuam sendo as do Google.
- **Criação rápida com linguagem natural**: `Ligar pro cliente amanhã ~trabalho #urgente`
  - datas: `hoje`, `amanhã`, `depois de amanhã`, `segunda` … `domingo`, `30/10`, `sem data`
  - `~lista` escolhe a lista do Google; `#etiqueta` adiciona (ou cria) uma etiqueta local
- **⌥Espaço** abre a criação rápida de qualquer lugar, mesmo com o app em segundo plano.
- **Sincronização contínua**: a cada 30 s por padrão (dá para mudar), de forma incremental; também ao abrir o popover, ao acordar o Mac e na virada do dia. As alterações aparecem na hora no app e são enviadas ao Google em seguida. Um cache local faz o app abrir na hora, mesmo sem internet.
- Opção **Abrir ao iniciar o Mac**.

## 1. Credenciais do Google (uma vez só)

O app conversa direto com as APIs do Google usando a sua conta, sem nenhum servidor no meio. Para isso você precisa de um "ID do cliente OAuth" próprio:

1. Abra o [Google Cloud Console](https://console.cloud.google.com/) e crie um projeto (ex.: `Tasker`).
2. Em **APIs e serviços → Biblioteca**, ative a **Google Tasks API** e a **Google Calendar API**.
3. Em **APIs e serviços → Tela de consentimento OAuth** (Google Auth Platform):
   - Tipo de usuário: **Externo**. Preencha nome do app e e-mail.
   - Em **Público-alvo / Usuários de teste**, adicione o seu e-mail.
   - **Importante:** depois clique em **Publicar app** (status "Em produção"). Enquanto o app estiver em modo "Teste", o Google derruba o login a cada 7 dias. Como o app não é verificado, no login vai aparecer "O Google não verificou este app": clique em **Avançado → Acessar Tasker**. Isso é normal para um app de uso pessoal.
4. Em **APIs e serviços → Credenciais → Criar credenciais → ID do cliente OAuth**:
   - Tipo de aplicativo: **App para computador**.
   - Copie o **Client ID** e o **Client Secret**.
5. Abra o Tasker, cole os dois e clique em **Entrar com Google**. O login acontece no navegador e depois volta para o app.

Os tokens ficam em `~/Library/Application Support/Tasker/secrets.json`, legível só pelo seu usuário.

## 2. Instalar

1. Baixe o `Tasker.zip` do [último release](https://github.com/pedroydzito/tasker/releases/latest), descompacte e arraste o `Tasker.app` para **Aplicativos**.
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
