# optimizely

Optimizely product knowledge for Claude Code, one skill per product. Each skill says how to
detect the product in a codebase, the patterns to follow, the security rules, how to test, and
how to deploy and verify.

## Skills

| Skill | Product | Status |
|---|---|---|
| `optimizely-cms12` | CMS 12 (PaaS, ASP.NET Core) | Available |
| `optimizely-cms13` | CMS 13 (.NET 10), and the upgrade from 12 | Available |
| `optimizely-cms-saas` | SaaS CMS | Planned |
| `optimizely-graph` | Optimizely Graph | Planned |
| `optimizely-search-navigation` | Search & Navigation (formerly Find) | Planned |
| `optimizely-commerce-customized` | Customized Commerce 14 | Planned |
| `optimizely-commerce-configured` | Configured Commerce | Planned |
| `optimizely-odp` | Data Platform (ODP) | Planned |
| `optimizely-ocp` | Connect Platform (OCP) apps | Planned |
| `optimizely-opal` | Opal tools and agents | Planned |
| `optimizely-experimentation` | Feature and Web Experimentation | Planned |

## Use

Install it from the `zion` marketplace beside `crew`, or on its own:

```
/plugin install optimizely@zion
```

Claude loads a skill when its description matches the task. Under `crew`, `backend-dotnet`
tells the backend worker to load the product skills whose markers the project carries.

Optimizely ships often. Each skill ends with its docs source; check version-specific details
there before you rely on them.
