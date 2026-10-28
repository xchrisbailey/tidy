# Domain docs

## Before exploring

Read root `GLOSSARY.md` and any ADRs in `docs/adr/` relevant to the work.

If these files are absent, proceed silently. Domain modeling creates
documentation lazily when terms or decisions are resolved.

## Layout

This repo uses a single context:
- `GLOSSARY.md`: domain terminology.
- `docs/adr/`: architectural decisions.

## Vocabulary

Use glossary terms in issue titles, proposals, hypotheses, and tests.
Respect explicitly avoided synonyms. If a needed concept is missing,
reconsider the term or note the gap for domain modeling.

## ADR conflicts

Explicitly flag proposals that contradict an existing ADR, citing the
decision and explaining why it is worth reopening.
