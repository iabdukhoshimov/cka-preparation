#!/usr/bin/env bash
# Delete the practice cluster. Recreating takes ~2 minutes, so reset freely after breaking things.
set -euo pipefail
kind delete cluster --name cka
