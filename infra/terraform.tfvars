# =================================================================
# 変数の実値
#   variables.tf で定義した変数に与える具体的な値
# Last updated: 2026-10-28 09:40:00
#   公開版: aws_account_id はダミー値（123456789012）。利用時は自分の環境の値に書き換える
# =================================================================

aws_region        = "ap-northeast-1"
assume_profile    = "ts-030-usr-build"
aws_account_id    = "123456789012"
build_role_name   = "ts-030-role-build"
prj_prefix        = "ts-030"
project_tag       = "ts-030"
vpc_cidr          = "10.0.0.0/16"
subnet_cidr       = "10.0.1.0/24"
availability_zone = "ap-northeast-1a"

# S3
s3_expire_days         = 30
s3_notification_suffix = ".conf"
