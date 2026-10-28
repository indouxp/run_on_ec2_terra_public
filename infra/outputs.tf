# =================================================================
# 出力値
#   後続タスク（SG・EC2 等）から参照する ID を出力する
# Last updated: 2026-06-21 16:24:00
# =================================================================

# VPC ID
output "vpc_id" {
  description = "作成した VPC の ID"
  value       = aws_vpc.main.id
}

# サブネット ID
output "subnet_id" {
  description = "作成したサブネットの ID"
  value       = aws_subnet.main.id
}

# インターネットゲートウェイ ID
output "internet_gateway_id" {
  description = "作成したインターネットゲートウェイの ID"
  value       = aws_internet_gateway.main.id
}

# ルートテーブル ID
output "route_table_id" {
  description = "作成したルートテーブルの ID"
  value       = aws_route_table.public.id
}

# セキュリティグループ ID
output "security_group_id" {
  description = "作成したセキュリティグループの ID"
  value       = aws_security_group.main.id
}

# Lambda 実行ロール ARN
output "lambda_role_arn" {
  description = "Lambda 実行ロールの ARN"
  value       = aws_iam_role.lambda.arn
}

# EC2 実行ロール ARN
output "ec2_role_arn" {
  description = "EC2 実行ロールの ARN"
  value       = aws_iam_role.ec2.arn
}

# オペレーション用ロール ARN（ts-030-usr-operate が AssumeRole する）
output "operate_role_arn" {
  description = "データ運用ロールの ARN"
  value       = aws_iam_role.operate.arn
}

# Lambda 関数名
output "lambda_function_name" {
  description = "作成した Lambda 起動関数の名前"
  value       = aws_lambda_function.lmd_010.function_name
}

# S3 バケット名（in/out）
output "s3_bucket_names" {
  description = "作成した S3 バケット名のマップ"
  value       = { for k, b in aws_s3_bucket.this : k => b.id }
}
