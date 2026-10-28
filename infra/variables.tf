# =================================================================
# 変数定義
#   各リソースで共通利用する設定値を変数として定義する
#   実値は terraform.tfvars で与える
# Last updated: 2026-09-22 17:18:05
# =================================================================

# AWS リージョン
variable "aws_region" {
  description = "リソースを作成する AWS リージョン"
  type        = string
  default     = "ap-northeast-1"
}

# infra 実行時に構築ロールを AssumeRole する起点プロファイル名
#   AssumeRole 権限のみを持つ ts-030-usr-build を使い、管理者は常用しない
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
  description = "infra が AssumeRole する構築ロール名"
  type        = string
  default     = "ts-030-role-build"
}

# プロジェクトプレフィックス（全リソース名の先頭に付与）
variable "prj_prefix" {
  description = "リソース名のプレフィックス"
  type        = string
  default     = "ts-030"
}

# Project タグの値（コスト管理・リソース識別用）
variable "project_tag" {
  description = "全リソースに付与する Project タグの値"
  type        = string
  default     = "ts-030"
}

# VPC の CIDR ブロック
variable "vpc_cidr" {
  description = "VPC に割り当てる CIDR ブロック"
  type        = string
  default     = "10.0.0.0/16"
}

# サブネットの CIDR ブロック
variable "subnet_cidr" {
  description = "サブネットに割り当てる CIDR ブロック"
  type        = string
  default     = "10.0.1.0/24"
}

# サブネットを配置するアベイラビリティゾーン
variable "availability_zone" {
  description = "サブネットを配置する AZ"
  type        = string
  default     = "ap-northeast-1a"
}

# S3 ライフサイクルでオブジェクトを削除するまでの日数（in/out 共通）
#   入出力ファイルは一時的なデータのため、既定 30 日で自動削除する
variable "s3_expire_days" {
  description = "S3 バケットのオブジェクトを削除するまでの日数"
  type        = number
  default     = 30
}

# S3 イベント通知（トリガー）のサフィックスフィルタ
#   実行設定ファイル（.conf）のアップロードのみを起動契機にする
variable "s3_notification_suffix" {
  description = "S3 トリガーで通知対象とするオブジェクトのサフィックス"
  type        = string
  default     = ".conf"
}
