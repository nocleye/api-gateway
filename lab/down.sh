#!/usr/bin/env bash
# Deletes the k3d cluster created by up.sh (and everything running in it).
set -euo pipefail
CLUSTER="${CLUSTER:-nocleye-obs}"
k3d cluster delete "$CLUSTER"
