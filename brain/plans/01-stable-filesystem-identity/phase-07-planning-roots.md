# 7 — Route remaining planning root checks

Back to [[plans/01-stable-filesystem-identity/overview]].

**Goal:** Natural-language and content naming use the same continuity decisions as
direct sorting. Both existing ADRs still apply.

**Changes:** `Sources/TidyCore/NaturalLanguagePlanning.swift`,
`Sources/TidyCore/ContentNaming.swift`, `Tests/TidyCoreTests/NaturalLanguageTests.swift`.

**Data structures:** Root proof references in planning outcomes; no new model
response format or inference authority.

**Routing:** Planning-interface integration.

**Static verification:** Remove authority decisions based on raw identity equality
at these call sites; keep evidence budgets and complete-plan validation unchanged.
Run Swift/lint checks and the unchanged request suites.

**Runtime verification:** Qualified root rewrite, replaced root, unsupported/legacy
root refusal, stale content and unchanged model-plan validation. Synthetic model
responses establish validation behavior, not naming-quality qualification.
