# Agent entry point

This repository is the standalone Dragonwilds **Mod Manager shell**. It hosts
drop-in modules; each module is a separate repository (`RSDW-ModManager-HotSwap`,
`RSDW-ModManager-Map`). For every task in this project, read these files before
changing code:

1. `.agent/SKILLS.md`, then every skill it marks as required. That includes
   `rsdw-mod-development`, which routes into `Docs/KnowledgeBase/` for any code
   that touches UE4SS or game objects.
2. `HANDOFF.md` — current work, recent changes, validation and next action.
3. `.agent/WORKSPACE.md` — paths and component map.
4. `README.md` — install, module contract and safety boundary.
5. `Docs/ROADMAP.md` — implementation state.
6. `Docs/TEST_PLAN.md` — live tests; unchecked means not proven in game.

Rules:

- Shell code must not know what any module does. Anything specific to one module
  belongs in that module's repository, behind the module contract in `README.md`.
- Other installed mods are not part of this project. Do not copy their code and
  do not introduce a runtime dependency on them.
- A module repository must work when dropped into `Modules/` with nothing else
  but this shell.

Before handing work to another tool or ending a meaningful implementation
session, update `HANDOFF.md` with:

- the active objective and exact next step;
- files changed and why;
- commands/tests run and their results;
- live Dragonwilds results, clearly separated from static validation;
- unresolved risks or assumptions.

Preserve `%LOCALAPPDATA%/RSDWModManager` user data. Keep this project PC-only.
Parse every changed Lua file and validate every changed JSON file. Never mark a
gameplay checkbox complete until the user or logs confirm it inside Dragonwilds.
Run `Tools/Test-PublicPackage.ps1` before a public commit or handoff.
