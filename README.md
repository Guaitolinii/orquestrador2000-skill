# orquestrador: a Claude Code skill that splits coding work across three models

**English** | [Português (Brasil)](README.pt-BR.md)

`orquestrador` ("orchestrator" in Portuguese) is a [Claude Code](https://claude.com/claude-code) skill that divides a programming task between three models, so the expensive one only does the part that needs judgment:

| Role | Who | What it does |
|---|---|---|
| **Build** | Gemini, through the [`omp`](https://github.com/can1357/oh-my-pi) CLI (Antigravity CLI `agy` as fallback) | Implements the feature, writes the tests, runs them |
| **Review** | Claude (your main session) | Writes the spec, verifies the result itself, tries to break it, approves or sends it back |
| **Commit** | A Haiku subagent | Stages an exact list of approved files and creates the commit |

The author of the code is never the one who approves it. That separation is what makes the review worth something.

> The skill file itself (`skills/orquestrador/SKILL.md`) is written in Brazilian Portuguese, because those are the instructions Claude follows. Claude talks to you in whatever language you use.

## Why use it

What I measured on one real run (details below), not marketing:

- **The review caught real bugs that the builder's own tests missed.** Gemini reported "10 tests pass". Two defects were still in the code: a CSV without a header silently lost its first row, and the price `nan` was accepted as valid. Both were reproduced by running the code, then fixed in one feedback round.
- **Fast builds.** Gemini 3.8 Flash through `omp` built small modules in 9 to 43 seconds and fixed review feedback in 13 to 68 seconds, resuming the same session. The `agy` fallback took 37 seconds to 2 minutes for similar work.
- **Clean history.** The Haiku subagent gets a closed list of files, so build artifacts (`__pycache__`, logs) never reach the commit. In a separate test, `omp commit` (which stages every modified file) proposed an extra commit containing only `.pyc` files.
- **Your work stays safe.** Everything happens on a dedicated branch created from a clean tree. Nothing is pushed, merged or deleted without you asking.
- **Cheaper context for the main model.** Claude spends tokens on the spec, the review and the decision. The typing is done by another model.

What I did **not** measure: how many Claude tokens the whole flow saves compared with Claude doing the task alone. Do not take a savings number from this README.

## How it works

1. **Prepare.** Checks that the folder is a git repository with a clean tree and creates a branch `orquestrador/<topic>`. Not a git repository, or you do not want commits? No commit step.
2. **Clarify and specify.** Ambiguous request: runs `superpowers:brainstorming`. Several steps: `superpowers:writing-plans`. Then writes a spec for Gemini, who cannot see the conversation. The spec must include acceptance criteria, how to test, **a line for every invalid input** (missing header, empty value, negative, `nan`, wrong encoding...) and tests written first.
3. **Build.** `omp -p --model google-antigravity/gemini-3.8-flash ...` in the project folder, output redirected to a file.
4. **Review.** Claude re-runs everything itself (a builder's "tests pass" counts as unverified), runs an edge-case probe script, and, for diffs over about 100 lines or code that parses input, handles money or touches security, dispatches an independent reviewer subagent. Feedback goes back to the same Gemini session with `omp -c`, at most 3 rounds. After the second failed round it runs `superpowers:systematic-debugging`.
5. **Commit.** A Haiku subagent stages the exact files, writes the commit message in the project's style and returns the hash. Claude checks the commit itself.
6. **Finish.** `superpowers:finishing-a-development-branch` offers merge, PR, keep or discard, and waits for your choice. No push, ever, by itself.

## Requirements

| Needed | Why | How to get it |
|---|---|---|
| [Claude Code](https://claude.com/claude-code) | Runs the skill | Follow the official install guide |
| `git` | Branches and commits | https://git-scm.com |
| **`omp`** (Oh My Pi) | Runs Gemini headlessly (`omp -p`) | macOS/Linux: `brew install can1357/tap/omp` or `mise use -g github:can1357/oh-my-pi`. Windows: follow the install instructions in the [upstream repository](https://github.com/can1357/oh-my-pi) |
| A Gemini login inside `omp` | The builder model | Run `omp login` and pick the provider `google-antigravity`. Then `omp models google-antigravity` should list `gemini-3.8-flash` |
| **superpowers** plugin | The process skills the flow calls (brainstorming, code review, debugging...) | In Claude Code: `/plugin marketplace add obra/superpowers-marketplace` then `/plugin install superpowers@superpowers-marketplace` |
| Python (optional) | Edge-case probe scripts in Python projects | https://python.org |
| `agy` Antigravity CLI (optional) | Fallback builder if `omp` fails | https://antigravity.google/docs/cli-using. To use it from the skill, also install the [antigravity-for-claude-code](https://github.com/yuting0624/antigravity-for-claude-code) plugin, which provides `agy-delegate` |

The model name `gemini-3.8-flash` depends on your plan. If your account lists a different one, edit it in `SKILL.md`.

## Install

```bash
git clone <this repository>
cd orquestrador2000-skill

# macOS / Linux / Git Bash on Windows
mkdir -p ~/.claude/skills
cp -r skills/orquestrador ~/.claude/skills/

# check that everything is in place (add --smoke to call Gemini for real)
bash scripts/check-setup.sh --smoke
```

PowerShell:

```powershell
New-Item -ItemType Directory -Force "$HOME\.claude\skills" | Out-Null
Copy-Item -Recurse skills\orquestrador "$HOME\.claude\skills\"
```

Restart Claude Code so it discovers the skill.

## How to use it

Open Claude Code in the project folder and ask in plain words:

```
/orquestrador add CSV import to the inventory module, with a summary report
```

or

```
let gemini build this and you review it: a function that converts markdown tables to HTML
```

Tips for good results:

- Say what must happen with **bad input**. The two bugs in the measured run came from exactly that gap in the spec.
- Tell it when you do not want commits ("no commits").
- Small changes (a line or two) are not worth delegating, and the skill will say so.
- Review the final branch yourself before merging. The skill never merges for you.

## A measured run

One run on Windows 11 with Git Bash, 2026-10-17. Task: a module that loads stock items from CSV, summarizes and formats them (about 150 lines of code and 290 of tests, reusing an existing dataclass).

| Step | Time | Result |
|---|---|---|
| Gemini builds (`omp`, thinking low) | 43 s | Reported 10 passing tests |
| Claude verification and edge probe | seconds | Found `nan`/`inf` accepted as prices |
| Independent reviewer (Sonnet subagent) | about 60 s, about 88k tokens | Confirmed `nan`, found the silent header problem, no critical issues |
| Feedback round to Gemini (`omp -c`) | 68 s | 21 tests, every defect re-checked by Claude |
| Haiku commit | 30 s, about 65k tokens | Commit with exactly the 2 intended files, no push |

It is one run, not a benchmark. The Haiku and reviewer subagents have a large fixed token overhead, which is why the reviewer is conditional on diff size and risk.

## Safety notes

- `omp` approves all tool calls by default (`tools.approvalMode = yolo`). So Gemini can write files and run commands without asking. That is why the skill insists on a **dedicated branch from a clean tree**: anything bad is thrown away with `git switch` and `git branch -D`. Outside git, the skill asks first.
- `--approval-mode write` is a stricter option: Gemini can write files but not run the shell. Claude then runs the tests.
- It is not a sandbox. I did not test whether `omp` can write outside the folder you give it.
- Never pipe the output of `omp` or `agy` (`omp ... | head`). They keep the pipe open and the command looks hung. Redirect to a file.
- The commit subagent is forbidden from `push`, `--amend`, `--no-verify` and from touching files outside its list.

## Troubleshooting

`SKILL.md` has a table of common failures (permission denied, quota, wrong model, timeouts, hung commands). First step is always `bash scripts/check-setup.sh --smoke`.

## Credits and license

Built on top of [Oh My Pi](https://github.com/can1357/oh-my-pi) by can1357, [superpowers](https://github.com/obra/superpowers) by obra and, for the optional fallback, [antigravity-for-claude-code](https://github.com/yuting0624/antigravity-for-claude-code) by yuting0624. This project is not affiliated with them, with Anthropic or with Google.

MIT License, see [LICENSE](LICENSE).
