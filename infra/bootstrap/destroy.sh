#!/usr/bin/env bash
# terraform が失敗したとき、tee ではなく terraform の終了コードを返す（pipefail が無いと常に 0）
set -o pipefail

terraform destroy -no-color 2>&1 |
  tee destroy_$(date +%Y%m%d_%H%M%S).log
