# Agent skills for punk-lang

Skills for coding agents (Claude Code, Codex, and others that read
`SKILL.md`), one per kind of task. `src/punk/llms.txt` is the reference for
the language. A skill is the recipe for one task, with the commands and
the checks that show the task is done.

| Skill | When |
|---|---|
| [`punk-check-loop`](punk-check-loop/SKILL.md) | writing or changing any `.punk` file: fmt, check, fix, repeat |
| [`punk-endpoint`](punk-endpoint/SKILL.md) | adding an HTTP endpoint to a server app |
| [`punk-migration`](punk-migration/SKILL.md) | changing a `table`: columns, renames, policies |
| [`punk-tui-screen`](punk-tui-screen/SKILL.md) | adding a screen or a key to a terminal app |

To use them in a project, copy (or link) the folders into the agent's skill
folder, such as `.claude/skills/` for Claude Code. `templates/<platform>/AGENTS.md`
is a starting `AGENTS.md` for a new app on each platform.
