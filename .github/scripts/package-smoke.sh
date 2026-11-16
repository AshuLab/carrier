#!/bin/bash
# Packs the package, installs the tarball in an empty project and runs what only an install can break: the binary starts, and both databases
# open and migrate from the installed files (the migrations are copied into dist by the build script, not compiled).
# Run by CI (Carrier Engine / Package smoke); run it by hand from anywhere in the clone.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

cd "$ROOT"
pnpm build
pnpm pack --pack-destination "$TMP"

mkdir "$TMP/app"
cd "$TMP/app"
echo '{"private":true}' > package.json
pnpm add "$TMP"/*.tgz

pnpm exec carrier --version
pnpm exec carrier schema > /dev/null
SMOKE_DIR="$TMP" node --input-type=module -e "
  import { openDatabase } from '@ashulab/carrier/dist/storage/db.js';
  import { openChatDatabase } from '@ashulab/carrier/dist/chat/db.js';
  openDatabase(process.env.SMOKE_DIR + '/engine.db');
  openChatDatabase(process.env.SMOKE_DIR + '/chat.db');
  console.log('both databases migrated');
"
