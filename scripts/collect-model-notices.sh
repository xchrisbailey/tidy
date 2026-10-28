#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

# Generate redistributable notices from the exact resolved checkouts, without adding a runtime dependency.
out="Packaging/Notices"
mkdir -p "$out"
while IFS= read -r -d '' file; do
  relative="${file#.build/checkouts/}"
  target="$out/${relative//\//__}"
  cp -f "$file" "$target"
  chmod u+w "$target"
done < <(find .build/checkouts -type f \( -name 'LICENSE' -o -name 'LICENSE.txt' -o -name 'LICENSE.md' -o -name 'LICENSE.MIT' -o -name 'NOTICE' -o -name 'NOTICE.txt' \) -print0)
cp Package.resolved "$out/Package.resolved.json"
# The conversion repository declares Apache-2.0 but does not include a LICENSE file.
# Archive the upstream license at a reviewed immutable source revision, not mutable main.
curl --fail --silent --show-error --location --proto '=https' --proto-redir '=https' --tlsv1.2 \
  'https://huggingface.co/Qwen/Qwen3-4B-Instruct-2507/resolve/cdbee75f17c01a7cc42f958dc650907174af0554/LICENSE' \
  -o "$out/Qwen3-LICENSE.txt"
curl --fail --silent --show-error --location --proto '=https' --proto-redir '=https' --tlsv1.2 \
  'https://huggingface.co/mlx-community/Qwen3-4B-Instruct-2507-4bit/resolve/50d427756c6b1b2fe0c0a10f67fbda1fc8e82c1b/README.md' \
  -o "$out/Model-Conversion-Card.txt"
