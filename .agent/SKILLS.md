# Project skills

Project-specific skills are vendored here so agents do not need access to one
another's global configuration.

## Required for Mod Manager work

- `skills/rsdw-mod-manager-ui/SKILL.md` — architecture, interaction design,
  reload safety, persistence and gameplay-validation rules for this standalone
  UE4SS project.

Read the skill completely before changing module UI, module behavior,
persistence, reload handling or gameplay integration.

## Required for any code that touches UE4SS or game objects

- `skills/rsdw-mod-development/SKILL.md` — load protocol, task routing into
  `Docs/KnowledgeBase/`, the hard crash rules, evidence gates (nothing is
  proven on our build until recorded), the licence gate and a self-review
  checklist. Read it completely before writing hooks, scans, UI, input, map,
  item, save or Mod Menu code. It applies together with the Mod Manager skill;
  where they differ, the Mod Manager skill and `README.md` win (for example
  PC-only: no controller work for the Mod Manager).

Client-owned system skills are intentionally not copied into this repository.
They can change with the client and are not part of this project's behavior.

