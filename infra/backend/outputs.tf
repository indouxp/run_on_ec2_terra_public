# =================================================================
# 出力値（state 用バケットのルートモジュール）
# Last updated: 2026-09-22 01:46:37
# =================================================================

# state 用バケット名（infra/provider.tf の backend "s3" の bucket に指定する値）
output "tfstate_bucket_name" {
  description = "Terraform state 用 S3 バケット名"
  value       = aws_s3_bucket.tfstate.bucket
}

# state 用バケットの ARN（構築ロールの権限設定で参照する値）
output "tfstate_bucket_arn" {
  description = "Terraform state 用 S3 バケットの ARN"
  value       = aws_s3_bucket.tfstate.arn
}
