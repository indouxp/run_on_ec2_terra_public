# =================================================================
# Provider 設定（ブートストラップ）
#   構築ロール ts-030-role-build を作成するための最初の1回だけ使用する。
#   ここでは AssumeRole せず、ロール管理ユーザー（ts-030-usr-role-admin）で直接実行する。
#   ts-030-usr-role-admin は ts-030-* ロールの作成/削除権限のみを持ち、admin は常用しない。
# Last updated: 2026-06-21 18:19:39
# =================================================================

terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# ロール管理プロファイルで直接実行する（assume_role なし）
provider "aws" {
  region  = var.aws_region
  profile = var.role_admin_profile

  # 作成する全リソースに Project タグを自動付与する
  default_tags {
    tags = {
      Project = var.project_tag
    }
  }
}
