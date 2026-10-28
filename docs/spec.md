# Tidy: accepted product decisions

Source: [Spec: On-device files assistant (v1)](https://app.notion.com/p/407b87b4b2788114a73adcb29b371b11).

This document records decisions accepted during the grilling session. The original rough spec remains context; its proposals and unresolved questions are not automatically accepted decisions. No implementation has started.

## Round 1: accepted October 28, 2026

- Optimize v1 for people periodically cleaning Downloads and Desktop. Privacy is a product guarantee.
- Execute clear requests without a preview. Ask for clarification when the intended outcome is ambiguous. Confirmation for a large task does not resolve ambiguity.
- Allow local inspection of file contents when it helps naming and sorting. Explain that capability clearly. Leave files unchanged when evidence is insufficient for a useful name. Content inspection does not authorize editing file contents.
- Keep file names, contents, and task instructions on the Mac. Defer cloud support, cloud settings, and a cloud provider architecture until there is a concrete need.
- Persist the history of completed changes across launches. Offer safe, best-effort undo when Tidy can identify the file and restore its original location. Report conflicts without overwriting files. History is not a backup, and reversibility is not guaranteed.

## Still unresolved

Folder traversal and exclusions, supported content types, naming quality, task limits, recovery details, platform and inference support, model management, distribution, pricing, and release acceptance criteria require further decisions.

