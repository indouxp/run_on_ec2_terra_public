#!/usr/bin/env bash
# terraform が失敗したとき、tee ではなく terraform の終了コードを返す（pipefail が無いと常に 0）
set -o pipefail

terraform apply -no-color 2>&1 |
  tee apply_$(date +%Y%m%d_%H%M%S).log
