#!/usr/bin/env bash
# terraform が失敗したとき、tee ではなく terraform の終了コードを返す（pipefail が無いと常に 0）
set -o pipefail
# 認証は provider.tf の profile（role_admin_profile = ts-030-usr-role-admin）で行う。
# AWS_PROFILE の指定は不要（provider の profile 指定が優先されるため）。

terraform apply -no-color 2>&1 |
  tee apply_$(date +%Y%m%d_%H%M%S).log
