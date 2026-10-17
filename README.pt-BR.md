# orquestrador: uma skill do Claude Code que divide o trabalho de programação entre três modelos

[English](README.md) | **Português (Brasil)**

`orquestrador` é uma skill do [Claude Code](https://claude.com/claude-code) que divide uma tarefa de programação entre três modelos, para que o mais caro faça só a parte que exige julgamento:

| Papel | Quem | O que faz |
|---|---|---|
| **Construir** | Gemini, pela CLI [`omp`](https://github.com/can1357/oh-my-pi) (Antigravity CLI `agy` como reserva) | Implementa, escreve os testes e roda |
| **Revisar** | Claude (sua sessão principal) | Escreve a especificação, verifica o resultado por conta própria, tenta quebrar o código, aprova ou devolve |
| **Commitar** | Um subagente Haiku | Prepara uma lista exata de arquivos aprovados e cria o commit |

Quem escreve o código nunca é quem o aprova. É essa separação que dá valor à revisão.

## Por que usar

O que eu medi em uma execução real (detalhes mais abaixo), sem marketing:

- **A revisão pegou defeitos reais que os testes do próprio construtor não pegaram.** O Gemini relatou "10 testes passaram". Ainda havia dois defeitos no código: um CSV sem cabeçalho perdia a primeira linha em silêncio, e o preço `nan` era aceito como válido. Os dois foram reproduzidos rodando o código e corrigidos em uma rodada de feedback.
- **Construção rápida.** O Gemini 3.8 Flash pelo `omp` construiu módulos pequenos em 9 a 43 segundos e corrigiu o feedback da revisão em 13 a 68 segundos, retomando a mesma sessão. A reserva `agy` levou de 37 segundos a 2 minutos em trabalho parecido.
- **Histórico limpo.** O subagente Haiku recebe uma lista fechada de arquivos, então lixo de build (`__pycache__`, logs) não entra no commit. Em um teste separado, o `omp commit` (que prepara todos os arquivos modificados) propôs um commit extra só com os `.pyc`.
- **O seu trabalho fica protegido.** Tudo acontece numa branch dedicada, criada a partir de uma árvore limpa. Nada é enviado, mesclado ou apagado sem você pedir.
- **Contexto mais barato para o modelo principal.** O Claude gasta tokens na especificação, na revisão e na decisão. Quem digita o código é outro modelo.

O que eu **não** medi: quantos tokens do Claude o fluxo inteiro economiza em comparação com o Claude fazendo a tarefa sozinho. Não tire um número de economia deste README.

## Como funciona

1. **Preparar.** Confere se a pasta é um repositório git com árvore limpa e cria a branch `orquestrador/<assunto>`. Não é git, ou você não quer commits? Não há etapa de commit.
2. **Esclarecer e especificar.** Pedido ambíguo: roda `superpowers:brainstorming`. Várias etapas: `superpowers:writing-plans`. Depois escreve uma especificação para o Gemini, que não vê a conversa. A spec precisa trazer critérios de aceite, como testar, **uma linha para cada entrada inválida** (cabeçalho ausente, valor vazio, negativo, `nan`, codificação errada...) e testes escritos primeiro.
3. **Construir.** `omp -p --model google-antigravity/gemini-3.8-flash ...` na pasta do projeto, com a saída redirecionada para arquivo.
4. **Revisar.** O Claude roda tudo de novo por conta própria (o "testes passaram" do construtor conta como não verificado), roda um script de sonda de casos de borda e, para diffs acima de cerca de 100 linhas ou código que lê entradas, mexe com dinheiro ou segurança, aciona um subagente revisor independente. O feedback volta para a mesma sessão do Gemini com `omp -c`, no máximo 3 rodadas. Depois da segunda rodada sem sucesso, roda `superpowers:systematic-debugging`.
5. **Commitar.** Um subagente Haiku adiciona os arquivos exatos, escreve a mensagem no estilo do projeto e devolve o hash. O Claude confere o commit por conta própria.
6. **Encerrar.** `superpowers:finishing-a-development-branch` oferece mesclar, abrir PR, manter ou descartar, e espera a sua escolha. Nenhum push por conta própria, nunca.

## O que precisa ser instalado

| Necessário | Para quê | Como obter |
|---|---|---|
| [Claude Code](https://claude.com/claude-code) | Executa a skill | Siga o guia oficial de instalação |
| `git` | Branches e commits | https://git-scm.com |
| **`omp`** (Oh My Pi) | Roda o Gemini sem interface (`omp -p`) | macOS/Linux: `brew install can1357/tap/omp` ou `mise use -g github:can1357/oh-my-pi`. Windows: siga as instruções de instalação do [repositório oficial](https://github.com/can1357/oh-my-pi) |
| Login do Gemini dentro do `omp` | O modelo construtor | Rode `omp login` e escolha o provedor `google-antigravity`. Depois `omp models google-antigravity` deve listar `gemini-3.8-flash` |
| Plugin **superpowers** | As skills de processo que o fluxo chama (brainstorming, revisão, depuração...) | No Claude Code: `/plugin marketplace add obra/superpowers-marketplace` e depois `/plugin install superpowers@superpowers-marketplace` |
| Python (opcional) | Scripts de sonda de borda em projetos Python | https://python.org |
| `agy`, o Antigravity CLI (opcional) | Construtor de reserva se o `omp` falhar | https://antigravity.google/docs/cli-using. Para usar pela skill, instale também o plugin [antigravity-for-claude-code](https://github.com/yuting0624/antigravity-for-claude-code), que fornece o `agy-delegate` |

O nome do modelo `gemini-3.8-flash` depende do seu plano. Se a sua conta listar outro, troque no `SKILL.md`.

## Instalação

```bash
git clone <este repositório>
cd orquestrador2000-skill

# macOS / Linux / Git Bash no Windows
mkdir -p ~/.claude/skills
cp -r skills/orquestrador ~/.claude/skills/

# confira se tudo está no lugar (com --smoke chama o Gemini de verdade)
bash scripts/check-setup.sh --smoke
```

PowerShell:

```powershell
New-Item -ItemType Directory -Force "$HOME\.claude\skills" | Out-Null
Copy-Item -Recurse skills\orquestrador "$HOME\.claude\skills\"
```

Reinicie o Claude Code para ele descobrir a skill.

## Como usar

Abra o Claude Code na pasta do projeto e peça com palavras simples:

```
/orquestrador adicione importação de CSV ao módulo de estoque, com relatório-resumo
```

ou

```
deixa o gemini construir e você revisa: uma função que converte tabelas markdown em HTML
```

Dicas para um bom resultado:

- Diga o que deve acontecer com **entrada ruim**. Os dois bugs da execução medida vieram exatamente dessa lacuna na especificação.
- Avise quando não quiser commits ("sem commits").
- Mudanças pequenas (uma ou duas linhas) não compensam a delegação, e a skill avisa.
- Revise você mesmo a branch final antes de mesclar. A skill nunca mescla por você.

## Uma execução medida

Uma execução no Windows 11 com Git Bash, em 17/10/2026. Tarefa: um módulo que carrega itens de estoque de um CSV, resume e formata (cerca de 150 linhas de código e 290 de testes, reaproveitando uma dataclass existente).

| Etapa | Tempo | Resultado |
|---|---|---|
| Gemini constrói (`omp`, thinking low) | 43 s | Relatou 10 testes passando |
| Verificação do Claude e sonda de borda | segundos | Achou `nan`/`inf` aceitos como preço |
| Revisor independente (subagente Sonnet) | cerca de 60 s, cerca de 88 mil tokens | Confirmou o `nan`, achou o problema silencioso do cabeçalho, nenhum defeito crítico |
| Rodada de feedback ao Gemini (`omp -c`) | 68 s | 21 testes, cada defeito reverificado pelo Claude |
| Commit do Haiku | 30 s, cerca de 65 mil tokens | Commit com exatamente os 2 arquivos previstos, sem push |

É uma execução só, não um benchmark. Os subagentes Haiku e revisor têm um overhead fixo grande de tokens, por isso o revisor só entra conforme o tamanho e o risco do diff.

## Notas de segurança

- O `omp` aprova todas as chamadas de ferramenta por padrão (`tools.approvalMode = yolo`). Ou seja, o Gemini pode gravar arquivos e rodar comandos sem pedir. Por isso a skill insiste em **branch dedicada a partir de árvore limpa**: qualquer estrago se descarta com `git switch` e `git branch -D`. Fora do git, a skill pergunta antes.
- `--approval-mode write` é uma opção mais restrita: o Gemini grava arquivos mas não roda o shell. Aí o Claude roda os testes.
- Não é uma sandbox. Não testei se o `omp` consegue escrever fora da pasta que você indica.
- Nunca use pipe na saída do `omp` ou do `agy` (`omp ... | head`). Eles seguram o pipe e o comando parece travado. Redirecione para arquivo.
- O subagente de commit é proibido de usar `push`, `--amend`, `--no-verify` e de mexer em arquivos fora da lista.

## Solução de problemas

O `SKILL.md` tem uma tabela de falhas comuns (permissão negada, cota, modelo errado, timeout, comando travado). O primeiro passo é sempre `bash scripts/check-setup.sh --smoke`.

## Créditos e licença

Construída sobre o [Oh My Pi](https://github.com/can1357/oh-my-pi) de can1357, o [superpowers](https://github.com/obra/superpowers) de obra e, para a reserva opcional, o [antigravity-for-claude-code](https://github.com/yuting0624/antigravity-for-claude-code) de yuting0624. Este projeto não é afiliado a eles, à Anthropic nem ao Google.

Licença MIT, veja [LICENSE](LICENSE).
