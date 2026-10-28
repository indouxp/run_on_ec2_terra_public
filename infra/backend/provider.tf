# =================================================================
# Provider 設定（state 用バケットのルートモジュール）
#   infra/ と同じく ts-030-usr-build を起点に構築ロール ts-030-role-build を
#   AssumeRole して実行する。このモジュール自体の state はローカルに置く
#   （バケットと付随設定のみのため、消失しても import で容易に復旧できる）。
# Last updated: 2026-09-22 01:46:37
# =================================================================

terraform {
  # Terraform 本体の必要バージョン（infra の backend で use_lockfile を使うため 1.10 以上）
  required_version = ">= 1.10"

  # 使用するプロバイダとそのバージョン制約（infra/ と揃える）
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# AWS プロバイダ本体（構築ロールを AssumeRole する）
provider "aws" {
  region  = var.aws_region
  profile = var.assume_profile

  # bootstrap で作成した構築ロールを引き受ける
  assume_role {
    role_arn = "arn:aws:iam::${var.aws_account_id}:role/${var.build_role_name}"
  }

  # 全リソースに Project タグを自動付与する
  default_tags {
    tags = {
      Project = var.project_tag
    }
  }
}
