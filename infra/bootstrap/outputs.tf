# =================================================================
# 出力値（ブートストラップ）
#   infra 側の provider が assume_role に使う ARN を出力する
# Last updated: 2026-06-21 18:19:36
# =================================================================

# 構築用ロールの ARN
output "build_role_arn" {
  description = "infra 側で AssumeRole する構築ロールの ARN"
  value       = aws_iam_role.build.arn
}
