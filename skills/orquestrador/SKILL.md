---
name: orquestrador
description: Use quando o usuário pedir "/orquestrador", "orquestra isso", "o gemini constrói e você revisa", "delega para o gemini" ou "deixa o gemini implementar", ou quando uma tarefa de programação for grande o bastante para compensar delegar (nova funcionalidade, novo script, refatoração, geração de testes, várias pastas ou arquivos) e a cota do Claude deva ser poupada, mesmo que o usuário não cite os modelos. Não use para ajustes de uma ou duas linhas, perguntas, revisão pura de código existente ou tarefas sem código.
---

# Orquestrador

Três papéis, três modelos. A divisão existe por custo e por qualidade: o Gemini faz o trabalho braçal (barato), o Claude fica com o julgamento (caro, então usado onde rende) e o Haiku fica com a parte mecânica do git. Quem escreve o código nunca é quem o aprova, e isso é o que dá valor à revisão.

| Papel | Quem | Faz | Não faz |
|---|---|---|---|
| Construir | Gemini, via `omp -p` (padrão) ou `agy-delegate` (reserva) | Implementa, cria arquivos, roda os testes que existirem | Commits, push, mexer fora da pasta combinada |
| Revisar | Claude (você, na sessão principal) | Escreve a especificação, lê o diff, roda testes, aprova ou devolve com feedback | Escrever a implementação (exceto correções triviais) |
| Commitar | Subagente Haiku (`Agent` com `model: "haiku"`) | Prepara os arquivos aprovados e cria o commit | Revisar, alterar código, push |

## Quando vale delegar

Cada chamada ao Gemini custa de 10 a 15 segundos pelo `omp` (de 40 segundos a 2 minutos pelo `agy`), mais o tempo de escrever a especificação e de revisar. Abaixo de uns 30 minutos de trabalho humano, ou em ajustes de poucas linhas, faça direto: delegar sai mais caro que fazer. Se o usuário pediu o orquestrador explicitamente, siga o fluxo mesmo assim, mas avise em uma linha que a tarefa é pequena.

## Skills do superpowers que apoiam cada fase

Invoque a skill pelo nome quando a condição valer. O Gemini não carrega skills do Claude, então a disciplina de TDD e de verificação vai escrita dentro da especificação, e o Claude aplica o resto.

| Fase | Skill | Condição |
|---|---|---|
| Antes da especificação | `superpowers:brainstorming` | Pedido ambíguo, sem critérios claros, ou que muda a estrutura do projeto. Não rode para tarefa já bem definida |
| Antes da especificação | `superpowers:writing-plans` | Mais de uma etapa. Cada tarefa do plano vira uma delegação com revisão própria |
| Especificação | `superpowers:test-driven-development` | Sempre que houver código testável: a spec pede os testes primeiro (ver etapa 1) |
| Revisão | `superpowers:verification-before-completion` | Sempre, antes de aprovar ou de dizer que algo passou |
| Revisão | `superpowers:requesting-code-review` | Diff acima de ~100 linhas, ou que toque em parsing de entrada, dinheiro ou segurança |
| Devolução | `superpowers:receiving-code-review` | Sempre que o feedback vier de um revisor, antes de repassar ao Gemini |
| Gemini falhou 2 vezes | `superpowers:systematic-debugging` | Na segunda rodada sem sucesso, antes da terceira |
| Depois do commit | `superpowers:finishing-a-development-branch` | Repositório git, com a branch pronta |

## Fluxo

### 0. Preparar o terreno

Descubra o que o projeto é antes de delegar, porque isso decide se há commit e como isolar o trabalho do Gemini.

```bash
cd <pasta do projeto>
git rev-parse --is-inside-work-tree   # é repositório?
git status --short                     # árvore limpa?
```

- **Repositório git com árvore limpa:** crie uma branch dedicada (`git switch -c orquestrador/<assunto-curto>`). O Gemini escreve nela, e o diff da branch é exatamente o que ele fez. Se a árvore está suja, pare e pergunte ao usuário o que fazer com as mudanças pendentes, porque misturar o trabalho dele com o do Gemini torna a revisão confusa.
- **Não é repositório git:** não há commit. Antes de delegar, liste os arquivos da pasta com data de modificação (ou copie a pasta, se for pequena), para conseguir dizer depois o que o Gemini alterou.
- **O usuário disse que não quer commits:** pule a etapa 4.

Confira também a permissão de escrita (próxima seção), senão o Gemini "termina" sem gravar nada.

### 1. Escrever a especificação (Claude)

**Antes de escrever, esclareça o pedido.** Se ele é ambíguo, invoque `superpowers:brainstorming` e feche o escopo com o usuário. Se tem várias etapas, invoque `superpowers:writing-plans` e delegue uma tarefa do plano por vez. Delegar um pedido mal definido só devolve código bonito que resolve a coisa errada.

O Gemini não vê esta conversa. Tudo o que ele precisa tem que estar no prompt, e uma especificação vaga volta como código que parece certo e não é. Escreva em arquivo (ex.: `SPEC_orquestrador.md` na pasta de scratchpad ou temporária, nunca dentro do projeto) e passe com `@arquivo` no `omp` (ou por stdin com `-` no `agy-delegate`). Inclua:

- **Objetivo** em uma ou duas frases, e por que ele existe.
- **Arquivos e pastas** envolvidos (caminhos reais) e o que já existe que ele deve reaproveitar.
- **Critérios de aceite** verificáveis (o que roda, o que retorna, quais casos de borda).
- **Convenções do projeto** que importam (linguagem, estilo, bibliotecas já em uso, o que não adicionar).
- **Entradas inválidas ou ausentes**, uma linha para cada: o que acontece com arquivo ou campo ausente, cabeçalho errado, valor vazio, negativo, `nan`/`inf`, codificação inesperada, duplicado. É a seção que mais evita retrabalho: no teste ponta a ponta, os dois defeitos que a revisão achou (cabeçalho nunca validado e preço `nan` aceito) vieram exatamente de lacunas aqui, e os testes do Gemini passaram mesmo assim. O que a spec não decide, o Gemini decide sozinho e em silêncio.
- **Testes primeiro** (`superpowers:test-driven-development`, escrito na spec porque o Gemini não carrega a skill): peça que escreva os testes de cada critério de aceite, rode para vê-los falhar, implemente, e rode de novo até passar. Peça ainda um teste por linha da seção de entradas inválidas.
- **Como testar** (comando exato, com `python -B` quando for Python para não deixar `__pycache__`), e a instrução de rodar esse comando antes de terminar e só dizer que passou se rodou.
- **Limites explícitos:** só mexer dentro de `<pasta>`; não fazer commit, push nem instalar dependências globais; não apagar arquivos que não criou; não colocar segredos no código.
- **Formato do relatório final:** lista curta dos arquivos criados/alterados e do que ficou por fazer.

Divida tarefas grandes em etapas que se revisem sozinhas. Um pedido enorme em uma chamada só produz um diff grande demais para revisar com atenção.

### 2. Construir (Gemini)

**Ferramenta padrão: `omp -p`.** Ela está instalada e logada no Gemini (provedor `google-antigravity`), e nos testes construiu em 9 a 15 segundos, contra 40 segundos a 2 minutos do `agy-delegate`, com ciclo de devolução incluso. O `agy-delegate` fica como reserva (seção abaixo).

```bash
omp -p --model google-antigravity/gemini-3.8-flash --thinking low --max-time 10m \
  --cwd "<pasta do projeto>" @"<caminho da SPEC.md>" > saida_gemini.txt 2> erro_gemini.txt </dev/null
echo "rc=$?"
```

Por que cada flag:

- `--model google-antigravity/gemini-3.8-flash` **sempre explícito.** Os papéis padrão do `omp` (`~/.omp/agent/config.yml`) dependem da configuração de cada um, então sem a flag ele pode usar outro modelo que não o Gemini. Fixar o modelo também impede que um modelo caro, como o Opus, seja usado por engano.
- `--thinking low` basta para implementação guiada por uma boa especificação, e é bem mais rápido. Suba para `medium` ou `high` só se a tarefa exigir raciocínio (algoritmo, concorrência).
- `--max-time` limita a sessão. Sem ele, um agente em loop só para quando você o mata.
- `--cwd` fixa a pasta de trabalho. `@arquivo` anexa a especificação sem estourar o limite de linha de comando.
- `</dev/null` evita que o `omp` espere entrada. **A sessão fica salva** (não use `--no-session` aqui), porque é ela que permite devolver feedback com `-c` na etapa 3. Use `--no-session` só em testes descartáveis.
- A resposta final do Gemini fica em `saida_gemini.txt`. O stderr mostra só "Working...", então não há resumo de tokens como no `agy`.

**Permissão.** O `omp` aprova tudo por padrão (`tools.approvalMode = yolo`, confira com `omp config get tools.approvalMode`), então o Gemini escreve arquivos e roda testes sem pedir. Isso equivale ao `--yolo` do `agy`, e a mesma regra vale: **só em branch dedicada com árvore limpa**, para qualquer estrago ser descartável com `git switch` e `git branch -D`. Em projeto sem git, pergunte antes. Se quiser um modo mais restrito, `--approval-mode write` permite gravar arquivos mas bloqueia o shell (medido: ele escreveu os arquivos e não pôde rodar os testes). Nesse caso, quem roda os testes é você, na revisão.

**Regras aprendidas no Windows com Git Bash (valem também nos outros sistemas):**

- **Nunca use pipe na saída** (`omp -p ... | head`). O teste com pipe passou dos 40 segundos e só terminou porque o `timeout` matou o processo, enquanto com redirecionamento para arquivo a mesma chamada leva 3 segundos. Sempre `> arquivo` e leia depois.
- Chamadas acima de ~2 minutos estouram o limite do Bash: use `run_in_background` e espere a notificação.
- Códigos de saída: `0` não garante que a tarefa foi feita (o Gemini pode relatar sucesso sem gravar nada). A verdade é o `git status` e o `git diff`.
- Se o `omp` pedir atualização ("update available"), isso não impede o uso. Não rode `omp update` no meio de uma tarefa.

**Reserva: `agy-delegate`.** Use se o `omp` falhar (login expirado, erro de provedor) ou se o usuário pedir o Antigravity CLI.

```bash
agy-delegate --tier flash --dir "<pasta do projeto>" --yolo --timeout 10m - \
  < SPEC.md > saida_gemini.txt 2> erro_gemini.txt
```

Mesmas regras de saída em arquivo e de branch dedicada para o `--yolo`. Sem permissão de escrita ele devolve código 0, resposta vazia e nada gravado (exit 15 no wrapper). A alternativa ao `--yolo` é uma regra `write_file(<pasta>)` em `~/.gemini/antigravity-cli/settings.json`, que só se grava depois de mostrar a linha ao usuário. Se `agy-delegate` não estiver no PATH, use o caminho completo em `~/.claude/plugins/cache/antigravity-for-claude-code/antigravity/<versão>/bin/`. Os códigos de saída dele: 3 vazio, 10 cota, 11 sem login, 12 timeout, 14 modelo indisponível, 15 permissão negada.

**Não confie no relatório do Gemini.** Ele pode dizer que terminou sem ter gravado nada, ou gravar em outro lugar. A verdade é o que o `git status` e o `git diff` mostram.

### 3. Revisar (Claude)

Aqui está o valor do Claude no fluxo. Revise como revisaria o código de um colega que não conhece o projeto:

1. `git status` e `git diff --stat`: o Gemini mexeu só no que devia? Arquivos inesperados, dependências novas, arquivos apagados ou lixo (logs, `.env`, saídas temporárias) são motivo de devolução.
2. Leia o diff inteiro, comparando com os critérios de aceite um a um. Procure: requisito esquecido, caso de borda ignorado, erro engolido em silêncio, segredo ou caminho fixo no código, duplicação de algo que já existia no projeto.
3. **Rode** o que foi pedido (testes, o script, o build), seguindo `superpowers:verification-before-completion`: nada passa até você ver a saída completa de uma execução sua, feita agora. Um teste que o Gemini disse ter passado conta como não verificado, e o relatório dele não prova nada (no teste ponta a ponta ele disse "passou" com dois defeitos reais no código).
4. **Sonda de borda.** Os testes do Gemini cobrem o que ele pensou em testar, e os defeitos moram no resto. Escreva um script curto (fora do projeto, rodando com `python -B`) que tenta quebrar o código com as entradas da seção "Entradas inválidas" da spec e com as que a spec esqueceu: vazio, só espaços, `nan`/`inf`, negativos, BOM, formato trocado, arquivo de 0 bytes. Imprima o resultado de cada caso e leia. No teste, uma única sonda de 9 casos achou o preço `nan` aceito como válido.
5. **Revisor independente, quando o diff justificar.** Se o diff passar de ~100 linhas ou tocar em parsing de entrada, dinheiro ou segurança, invoque `superpowers:requesting-code-review` e dispare um subagente com `Agent` (`subagent_type: "general-purpose"`, `model: "sonnet"`) usando o template `code-reviewer.md` daquela skill. Como o código ainda não foi commitado, `git diff` não mostra arquivos novos: diga ao revisor para **ler os arquivos direto**, passe o caminho da spec como requisito, a base (`git rev-parse --short HEAD`), e exija: somente leitura, `python -B -I` ao rodar qualquer coisa, sem subagentes, relatório abaixo de 600 palavras com cada defeito confirmado por leitura ou execução. Custo medido: ~88 mil tokens do Sonnet e ~1 minuto, então fica condicional. Em diffs pequenos, a verificação própria e a sonda bastam.
6. Decida:
   - **Aprovado:** vá para a etapa 4.
   - **Correção trivial** (poucas linhas, claramente certa): aplique você mesmo, porque uma volta de 30 segundos custa mais que o conserto. Registre o que mudou.
   - **Devolver:** se o feedback veio do revisor, siga `superpowers:receiving-code-review` antes de repassar: reproduza cada ponto você mesmo e mande ao Gemini só o que confirmou, com o exemplo que reproduz o defeito (no teste, os achados do revisor foram reproduzidos em segundos e um deles era mais amplo do que o relatório sugeria). Depois mande feedback específico e acionável (arquivo, problema, o que esperava) retomando a mesma conversa com `omp -p -c --model google-antigravity/gemini-3.8-flash --thinking low --cwd "<pasta>" "<feedback>" > saida.txt 2> erro.txt </dev/null` (no `agy-delegate`, é `--continue`). O `-c` retoma a sessão mais recente daquela pasta, então o Gemini já conhece o código que escreveu. Testado: o feedback "`titulo('')` deve devolver `''` e espaços extras devem colapsar" foi corrigido em 13 segundos, com testes novos passando. "Melhore o código" não serve; "em `parser.py`, `parse_date` não trata data vazia, devolva `None`" serve.

Limite de **3 rodadas** de devolução. Se a **segunda** devolução também não resolveu, invoque `superpowers:systematic-debugging` e descubra a causa raiz (spec ambígua, premissa errada do Gemini, bug no teste) antes da terceira, em vez de repetir o mesmo feedback com outras palavras. Se na terceira ainda não passou, pare: ou a especificação estava errada (reescreva), ou a tarefa é difícil demais para o Gemini Flash (faça você o trecho problemático, ou fale com o usuário). Insistir além disso só gasta tempo.

### 4. Commitar (Haiku), só se for repositório git

Só depois da aprovação. O commit é mecânico, por isso vai para o Haiku: chame a ferramenta `Agent` com `model: "haiku"` e `subagent_type: "general-purpose"`. Ele não tem o contexto da conversa, então o briefing precisa ser completo:

- A pasta do repositório e a branch atual.
- A **lista exata de arquivos** a incluir (você a tirou do `git status` na revisão). Ele deve adicionar cada um por nome, nunca `git add -A` nem `git add .`, para não levar lixo junto.
- A mensagem de commit pronta, ou a descrição do que mudou e por quê, pedindo que ele siga o estilo das últimas mensagens (`git log --oneline -10`). Se o projeto usa Conventional Commits, diga.
- As linhas de atribuição que o ambiente exigir (ex.: `Co-Authored-By` ao final da mensagem), copiadas literalmente do contexto da sessão.
- Proibições: sem `git push`, sem `--amend`, sem `--no-verify`, sem alterar nenhum arquivo, sem commitar nada fora da lista. Se um hook de commit falhar, ele **para e reporta** o erro, sem tentar contornar.
- O que devolver: hash do commit, `git show --stat` resumido, e qualquer anomalia.

Quando a mudança tem partes independentes (ex.: uma funcionalidade e seus testes, ou duas correções sem relação), peça um commit por unidade lógica, informando quais arquivos pertencem a cada um.

Depois, confira você mesmo com `git log -1 --stat`: a mensagem faz sentido e só os arquivos esperados entraram? Se o Haiku errou, corrija com um novo commit ou peça ao usuário, sem reescrever histórico por conta própria.

**Push nunca faz parte do fluxo.** Com a branch pronta, invoque `superpowers:finishing-a-development-branch` para apresentar ao usuário as opções (mesclar, abrir PR, manter ou descartar a branch) e **espere a escolha dele**: nada é mesclado, empurrado ou apagado sem pedido explícito. Termine dizendo a branch e o hash.

O commit do Haiku custou ~65 mil tokens nos dois testes, quase tudo overhead de contexto do subagente. Vale pela cota separada do Haiku. Se a cota dele for a mesma da sessão principal, ou se o usuário pedir economia máxima, o Claude pode fazer o commit direto com a mesma lista fechada de arquivos.

### 5. Relatar ao usuário

Feche em poucas linhas: o que o Gemini construiu, o que a revisão encontrou e como foi resolvido (quantas rodadas), o que foi verificado de verdade (comandos rodados e resultado), a branch e o(s) hash(es) dos commits, e o que ficou pendente ou incerto. Se você aplicou correções por conta própria, diga quais.

## Falhas comuns

| Sintoma | Causa provável | O que fazer |
|---|---|---|
| Gemini diz que terminou, nada mudou no `git status` | Escrita negada em modo headless (exit 15) | Regra `write_file(...)` ou `--yolo` em branch dedicada |
| Comando não retorna | Pipe na saída (`omp` e `agy`) ou MCP do `agy` demorando | Redirecionar para arquivo; rodar em background |
| `omp`: shell bloqueado ("requires approval") | Rodou com `--approval-mode write` | Normal nesse modo: rode os testes você mesmo, ou use o padrão em branch dedicada |
| `omp`: erro de provedor ou login | Credencial do Antigravity expirada | `omp login` no terminal do usuário, ou usar `agy-delegate` como reserva |
| `agy` exit 10 | Cota do Gemini | Esperar e retomar com `--continue`, ou avisar o usuário |
| `agy` exit 12 | Timeout | Aumentar `--timeout` ou quebrar a tarefa em etapas menores |
| `agy` exit 14 | Nome de modelo inexistente | Rodar `agy models` e usar um nome da lista |
| Diff enorme e confuso | Tarefa grande demais numa chamada só | Dividir a especificação em etapas |
| Haiku commitou arquivo a mais | Briefing sem lista fechada de arquivos | Novo commit corretivo e briefing mais explícito na próxima |
| Gemini passou nos próprios testes e o código tem defeito | Spec sem a seção de entradas inválidas, ou testes que só cobrem o caminho feliz | Sonda de borda na revisão e, na próxima spec, uma linha por entrada inválida |
| `__pycache__/` aparece como não rastreado | Testes rodados sem `-B` | `python -B` na spec e na revisão. Nunca entra na lista de arquivos do commit |

Se algo estranho persistir no `agy`, rode `agy-doctor` (com a saída em arquivo) antes de investigar à mão. No `omp`, `omp models google-antigravity` mostra se o modelo existe e os logs ficam em `~/.omp/logs/`.

## Por que o commit não usa `omp commit`

O `omp commit` existe e usa o Haiku (papel `commit` do `omp`), mas **prepara todos os arquivos modificados** (`No staged changes detected, staging all changes`). No teste, ele propôs um segundo commit só com os `.pyc` do `__pycache__` e a própria resposta ressalvou que talvez não devesse. O subagente Haiku com lista fechada de arquivos (etapa 4) evita esse lixo, então ele continua sendo o caminho. Se um dia usar o `omp commit`, só com `--dry-run` primeiro, `--no-changelog` (senão ele altera changelogs) e nunca com `--push`.
