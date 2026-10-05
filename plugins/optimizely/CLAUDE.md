# optimizely — quick reference for agents working on this plugin

Skills only: no agents, commands or hooks. Rules shared by every plugin:
[AGENTS.md](../../AGENTS.md). Keep this file accurate in the same commit as the change.

## Skill shape

Each `skills/optimizely-<product>/SKILL.md` has frontmatter `name:` + `description:` (the
description names the package or file markers that trigger it), then these sections in order:

- **Detect** — package references, config keys and files that mark the product, and which
  neighbouring product skills to load with it.
- Product sections — the patterns to follow, named for the product's own concepts.
- **Security**, **Testing**, **Deploy and verify** — where the product has them.
- **Sources** — the docs URL to check version-specific details against.

A skill states what differs for its product only. CMS 13 builds on CMS 12, so
`optimizely-cms13` lists the changes and the crew loads both.

## Wiring

- `crew`'s `backend-dotnet` names the product skills as `optimizely:<skill>`; validator §10
  checks that each such reference resolves to a skill here.
- Facts come from docs.optimizely.com. Optimizely ships often: re-check a skill's sources when
  you touch it, and never add an API name you have not seen in the docs.
