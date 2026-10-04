#!/usr/bin/env bash
# Compiles the app sources with the service checks and runs them.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$(mktemp -d)"
trap 'rm -rf "$OUT"' EXIT

swiftc -lsqlite3 -o "$OUT/service-checks" \
  "$ROOT"/Sources/AgentPulse/Models.swift \
  "$ROOT"/Sources/AgentPulse/ModelCatalog.swift \
  "$ROOT"/Sources/AgentPulse/StateStore.swift \
  "$ROOT"/Sources/AgentPulse/SubscriptionReader.swift \
  "$ROOT"/Sources/AgentPulse/UsageEngine.swift \
  "$ROOT"/Tests/ServiceChecks.swift

"$OUT/service-checks"
