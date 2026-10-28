# =================================================================
# Provider 設定
#   AWS プロバイダのバージョン固定とリージョン指定を行う
# Last updated: 2026-10-29 08:41:49
# =================================================================

terraform {
  # Terraform 本体の必要バージョン
  #   下の backend "s3" の use_lockfile が 1.10 以上を要求するため、それ未満の CLI は拒否する
  required_version = ">= 1.10"

  # 使用するプロバイダとそのバージョン制約
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    # 実行元グローバル IP 取得（security.tf の data "http"）で使用
    http = {
      source  = "hashicorp/http"
      version = "~> 3.0"
    }
    # Lambda デプロイパッケージの zip 化（compute.tf の data "archive_file"）で使用
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.0"
    }
  }

  # state のリモートバックエンド（改善対象 B-5 / BUG-003 の再発防止）
  #   バケットは infra/backend/ で作成。backend ブロックは変数を使えないため値を直書きする。
  #   認証は provider と同じく ts-030-usr-build → ts-030-role-build の AssumeRole。
  #   use_lockfile: S3 上の .tflock オブジェクトで排他する（DynamoDB 不要、Terraform 1.10+）
  #   公開版: role_arn のアカウント ID はダミー値。利用時は自分の環境の値に書き換える
  backend "s3" {
    bucket       = "ts-030-bkt-tfstate"
    key          = "infra/terraform.tfstate"
    region       = "ap-northeast-1"
    profile      = "ts-030-usr-build"
    assume_role  = { role_arn = "arn:aws:iam::123456789012:role/ts-030-role-build" }
    encrypt      = true
    use_lockfile = true
  }
}

# AWS プロバイダ本体。
#   AssumeRole 専用プロファイル（ts-030-usr-build）を起点に、構築ロール
#   ts-030-role-build を AssumeRole して実行する。管理者権限の常用を避ける。
provider "aws" {
  region  = var.aws_region
  profile = var.assume_profile

  # bootstrap で作成した構築ロールを引き受ける
  assume_role {
    role_arn = "arn:aws:iam::${var.aws_account_id}:role/${var.build_role_name}"
  }

  # このプロバイダで作成する全リソースに自動付与する共通タグ
  #   Project タグを一括付与し、付け忘れを防ぐ
  default_tags {
    tags = {
      Project = var.project_tag
    }
  }
}
