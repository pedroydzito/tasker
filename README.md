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

Os tokens ficam no Keychain do macOS.

## 2. Compilar e instalar

Precisa de macOS 15 ou mais novo e do Xcode (ou só das Command Line Tools: `xcode-select --install`).

```bash
git clone https://github.com/pedroydzito/tasker.git
cd tasker
make install      # compila, copia para /Applications e abre
```

Outros comandos: `make app` (só gera `build/Tasker.app`), `make run`, `make clean`.

Também dá para baixar o `Tasker.zip` gerado pelo GitHub Actions (aba **Actions → Build → Artifacts**). Como o app não é assinado com conta de desenvolvedor, depois de descompactar rode:

```bash
xattr -cr Tasker.app
```

> Dica: o KiteTasks também usa **⌥Espaço**. Se os dois estiverem abertos, desative o atalho em um deles.
>
> Depois de recompilar, o macOS pode perguntar se o Tasker pode acessar o Keychain. Escolha **Sempre permitir**.

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
