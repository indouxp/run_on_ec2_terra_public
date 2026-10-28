# =================================================================
# 変数定義（ブートストラップ）
# Last updated: 2026-06-21 18:19:42
# =================================================================

# AWS リージョン
variable "aws_region" {
  description = "リソースを作成する AWS リージョン"
  type        = string
  default     = "ap-northeast-1"
}

# 構築ロールの作成・削除を行う IAM ユーザーのプロファイル名（~/.aws/credentials のプロファイル）
#   ts-030-* ロールの作成/削除権限のみを持つ ts-030-usr-role-admin を使う（admin は常用しない）
variable "role_admin_profile" {
  description = "bootstrap で構築ロール ts-030-role-build を作成・削除するプロファイル名"
  type        = string
  default     = "ts-030-usr-role-admin"
}

# プロジェクトプレフィックス（リソース名の先頭に付与）
variable "prj_prefix" {
  description = "リソース名のプレフィックス"
  type        = string
  default     = "ts-030"
}

# Project タグの値
variable "project_tag" {
  description = "全リソースに付与する Project タグの値"
  type        = string
  default     = "ts-030"
}
