#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
# There is no verified qualification/approval record yet. An environment variable
# or a filled checkbox cannot substitute for the missing evidence and human review.
echo 'PUBLIC RELEASE BLOCKED: no Mac configuration is qualified.' >&2
echo 'Resolve and review docs/distribution.md prerequisites before implementing release promotion.' >&2
echo 'This command creates, signs, uploads and publishes nothing. Flags cannot override this gate.' >&2
exit 1
