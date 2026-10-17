#!/usr/bin/env bash
# check-setup.sh: verifica se tudo o que a skill "orquestrador" precisa esta instalado.
# Checks that everything the "orquestrador" skill needs is installed.
#
# Uso / Usage:
#   bash scripts/check-setup.sh            # verificacoes locais, rapidas / fast local checks
#   bash scripts/check-setup.sh --smoke    # alem disso, chama o Gemini de verdade (~5s) / also calls Gemini for real
#
# Nunca encadeia a saida do omp em pipe: o omp e o agy seguram o pipe e o comando parece travado.
# Never pipes omp output: omp and agy hold the pipe open and the command looks hung.

set -u

MODEL="google-antigravity/gemini-3.8-flash"
SMOKE=0
[ "${1:-}" = "--smoke" ] && SMOKE=1

FAIL=0
WARN=0
ok()   { printf '  [ok]   %s\n' "$1"; }
warn() { printf '  [warn] %s\n' "$1"; WARN=$((WARN + 1)); }
fail() { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL + 1)); }

TMP="$(mktemp)"
trap 'rm -f -- "${TMP:?}"' EXIT

run_to_file() { # run_to_file <timeout-seconds> <cmd...>; stdout+stderr -> $TMP, stdin fechado
  local secs="$1"; shift
  if command -v timeout >/dev/null 2>&1; then
    timeout "$secs" "$@" >"$TMP" 2>&1 </dev/null
  else
    "$@" >"$TMP" 2>&1 </dev/null
  fi
}

echo "orquestrador: verificacao de requisitos / setup check"
echo

echo "Obrigatorios / Required"
if command -v git >/dev/null 2>&1; then
  run_to_file 20 git --version; ok "git: $(head -n 1 "$TMP")"
else
  fail "git nao encontrado / not found (https://git-scm.com)"
fi

if command -v claude >/dev/null 2>&1; then
  run_to_file 30 claude --version; ok "Claude Code: $(head -n 1 "$TMP")"
else
  fail "claude (Claude Code) nao encontrado / not found (https://claude.com/claude-code)"
fi

if command -v omp >/dev/null 2>&1; then
  run_to_file 40 omp --version; ok "omp (Oh My Pi): $(head -n 1 "$TMP")"
  run_to_file 60 omp models google-antigravity
  if grep -q "gemini-3.8-flash" "$TMP"; then
    ok "modelo $MODEL listado / model listed"
  else
    warn "modelo gemini-3.8-flash nao apareceu em 'omp models google-antigravity'. Rode 'omp login' e escolha Google Antigravity, ou ajuste o nome do modelo na skill / run 'omp login' (Google Antigravity) or adjust the model name in the skill"
  fi
  run_to_file 30 omp config get tools.approvalMode
  mode="$(head -n 1 "$TMP")"
  case "$mode" in
    yolo) warn "omp tools.approvalMode = yolo: o Gemini escreve e roda comandos sem pedir. A skill so deve rodar em branch dedicada com arvore limpa / Gemini writes and runs commands unprompted; use only on a dedicated branch with a clean tree" ;;
    *)    ok "omp tools.approvalMode = ${mode:-?}" ;;
  esac
else
  fail "omp nao encontrado / not found (https://github.com/can1357/oh-my-pi)"
fi

PLUGINS="${HOME}/.claude/plugins/installed_plugins.json"
if [ -f "$PLUGINS" ] && grep -q '"superpowers@' "$PLUGINS"; then
  ok "plugin superpowers instalado / installed"
else
  fail "plugin superpowers nao encontrado / not found. No Claude Code: /plugin marketplace add obra/superpowers-marketplace  e  /plugin install superpowers@superpowers-marketplace"
fi

SKILL="${HOME}/.claude/skills/orquestrador/SKILL.md"
if [ -f "$SKILL" ]; then
  ok "skill instalada em / installed at ~/.claude/skills/orquestrador"
else
  fail "skill nao instalada / not installed. Copie skills/orquestrador para ~/.claude/skills/ / copy skills/orquestrador to ~/.claude/skills/"
fi

echo
echo "Opcionais / Optional"
if command -v agy >/dev/null 2>&1; then
  run_to_file 40 agy --version; ok "agy (Antigravity CLI, reserva / fallback): $(head -n 1 "$TMP")"
else
  warn "agy nao encontrado: sem a reserva se o omp falhar / not found: no fallback if omp fails (https://antigravity.google/docs/cli-using)"
fi
if command -v python >/dev/null 2>&1 || command -v python3 >/dev/null 2>&1; then
  ok "python disponivel (usado nas sondas de borda de projetos Python) / available (used for edge-case probes in Python projects)"
else
  warn "python nao encontrado: so necessario para projetos Python / only needed for Python projects"
fi

if [ "$SMOKE" -eq 1 ] && command -v omp >/dev/null 2>&1; then
  echo
  echo "Teste real / Smoke test (chama o Gemini / calls Gemini)"
  start=$(date +%s)
  run_to_file 90 omp -p --no-session --model "$MODEL" --thinking low --max-time 60 "Reply with exactly: PONG"
  rc=$?
  secs=$(( $(date +%s) - start ))
  if grep -q "PONG" "$TMP"; then
    ok "Gemini respondeu em ${secs}s / replied in ${secs}s"
  else
    fail "sem resposta valida (rc=$rc). Rode 'omp login' / no valid reply (rc=$rc). Run 'omp login'. Ultimas linhas / last lines: $(tail -n 3 "$TMP" | tr '\n' ' ')"
  fi
fi

echo
if [ "$FAIL" -gt 0 ]; then
  echo "Resultado / Result: $FAIL falha(s), $WARN aviso(s) / failure(s), warning(s)"
  exit 1
fi
echo "Resultado / Result: tudo certo, $WARN aviso(s) / all good, $WARN warning(s)"
