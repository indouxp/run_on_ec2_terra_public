# =================================================================
# 変数定義（state 用バケットのルートモジュール）
#   既定値は infra/variables.tf と揃える。実値は terraform.tfvars で与える
# Last updated: 2026-09-22 01:46:37
# =================================================================

# AWS リージョン
variable "aws_region" {
  description = "リソースを作成する AWS リージョン"
  type        = string
  default     = "ap-northeast-1"
}

# 構築ロールを AssumeRole する起点プロファイル名
variable "assume_profile" {
  description = "構築ロール ts-030-role-build を AssumeRole する起点プロファイル名"
  type        = string
  default     = "ts-030-usr-build"
}

# AWS アカウント ID（AssumeRole 対象ロールの ARN 構築に使用）
variable "aws_account_id" {
  description = "リソースを作成する AWS アカウント ID"
  type        = string
}

# 構築用ロール名（bootstrap で作成した ts-030-role-build）
variable "build_role_name" {
  description = "AssumeRole する構築ロール名"
  type        = string
  default     = "ts-030-role-build"
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

# state の旧バージョンを保持する日数（誤更新からの復旧猶予と容量のバランス）
variable "noncurrent_days" {
  description = "state の旧バージョンを削除するまでの日数"
  type        = number
  default     = 90
}
