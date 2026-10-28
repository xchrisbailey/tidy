# Tidy

Tidy helps people rename and sort files on their Mac through plain-language requests.

## Language

**Task**:
A user's request to rename or sort files in a chosen folder, together with the resulting changes.
_Avoid_: Job, cleanup run

**Plan**:
The proposed set of file renames and moves for a task.
_Avoid_: Task, preview

**Operation**:
An individual rename or move of a file.
_Avoid_: Task

**Undo history**:
The remembered record of changes Tidy completed, available for attempting to reverse those changes.
_Avoid_: Backup

**Undo conflict**:
A circumstance that prevents a recorded change from being reversed safely, such as an occupied original location or a file that can no longer be identified.

