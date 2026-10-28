# Issue tracker: GitHub

Issues and specs live in GitHub Issues for `xchrisbailey/tidy`.
Use the `gh` CLI from this directory.

## Conventions

- Before creating issues, verify the target with `gh repo view --json nameWithOwner`.
- Create: `gh issue create --title "..." --body-file <path>`.
- Read: `gh issue view <number> --json number,title,body,labels,comments`.
- List: `gh issue list --state open --json number,title,body,labels`.
- Comment: `gh issue comment <number> --body "..."`.
- Apply or remove labels: `gh issue edit <number> --add-label "..."` or `--remove-label "..."`.
- Close: post the explanation as a comment, then run `gh issue close <number>`.
  Post comments separately even when an issue is already closed.
- Use the label mappings in `triage-labels.md`.

When a skill says “publish to the issue tracker,” create a GitHub issue.
When it says “fetch the relevant ticket,” read the referenced issue.

## Parent issues and blocking

Use native GitHub sub-issues and issue dependencies when available.
With gh 2.94+, use `--parent` / `--add-sub-issue` and
`--blocked-by` / `--add-blocked-by`.

For older clients, use the GitHub API with issue database IDs, not issue numbers:
- Sub-issue: POST `repos/xchrisbailey/tidy/issues/<parent>/sub_issues`
  with `sub_issue_id=<child-db-id>`.
- Dependency: POST `repos/xchrisbailey/tidy/issues/<child>/dependencies/blocked_by`
  with `issue_id=<blocker-db-id>`.

Get a database ID with `gh api repos/xchrisbailey/tidy/issues/<number> --jq .id`.
If native relationships are unavailable, record `Part of #<parent>` and
`Blocked by: #<number>` in the child body, and list children in the parent.
A ticket is unblocked when every blocker is closed.

## Pull requests as a triage surface

**PRs as a request surface: no.**

## Wayfinding operations

- Map: one issue labelled `wayfinder:map`, containing Notes,
  Decisions-so-far, and Fog.
- Children: linked sub-issues labelled `wayfinder:<type>`, where type is
  research, prototype, grilling, or task.
- Frontier: open children with no open blockers and no assignee;
  first in map order wins.
- Claim: assign yourself with `gh issue edit <number> --add-assignee @me`
  before starting work.
- Resolve: comment with the answer, close the child, then append a gist
  and link to the map's Decisions-so-far.
