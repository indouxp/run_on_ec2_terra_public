# =================================================================
# ストレージ（WBS 2.3）
#   S3 バケット in/out / 共通設定 / バケットポリシー / ライフサイクル /
#   Lambda トリガー（イベント通知）
# Last updated: 2026-09-22 17:17:45
# =================================================================

# -----------------------------------------------------------------
# バケット本体
#   in（入力）/ out（出力）の2バケットを for_each で共通生成する。
#   バケット名は ${prj}-bkt-in / ${prj}-bkt-out。
# -----------------------------------------------------------------
resource "aws_s3_bucket" "this" {
  for_each = toset(["in", "out"])

  bucket = "${var.prj_prefix}-bkt-${each.key}"

  tags = {
    Name = "${var.prj_prefix}-bkt-${each.key}"
  }
}

# パブリックアクセスブロック（4項目すべて有効）
resource "aws_s3_bucket_public_access_block" "this" {
  for_each = aws_s3_bucket.this

  bucket                  = each.value.id
  block_public_acls       = true
  ignore_public_acls      = true
  block_public_policy     = true
  restrict_public_buckets = true
}

# 既定の暗号化（SSE-S3 / AES256 + バケットキー有効）
resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  for_each = aws_s3_bucket.this

  bucket = each.value.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

# 所有者制御（ACL 無効化 / BucketOwnerEnforced）
resource "aws_s3_bucket_ownership_controls" "this" {
  for_each = aws_s3_bucket.this

  bucket = each.value.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

# ライフサイクル（バケット全体を対象に N 日で削除）
#   Expiration のみ（Transition なし）で in/out 両方に適用する。
resource "aws_s3_bucket_lifecycle_configuration" "this" {
  for_each = aws_s3_bucket.this

  bucket = each.value.id

  rule {
    id     = "${each.value.bucket}-expire-${var.s3_expire_days}d"
    status = "Enabled"

    filter {} # プレフィックス絞り込みなし＝バケット全体

    expiration {
      days = var.s3_expire_days
    }
  }
}

# -----------------------------------------------------------------
# バケットポリシー = Deny フェンス（WBS 2.4e）
#   役割分担: 許可(grant)は各ロールの IAM インライン、境界(fence)はここ。
#   承認 principal 以外の「データ操作」を Deny し、真の多層防御にする。
#   - Principal:"*" + Condition StringNotLike aws:PrincipalArn で承認外を拒否
#     （NotPrincipal+Deny はセッション ARN を取りこぼすため使わない）。
#   - Deny 対象は data 操作のみ。管理系（PutBucketPolicy 等）は対象外にして
#     ts-030-role-build（Terraform 管理）がロックアウトされないようにする。
#   - 緊急/管理のため ts-usr-admin を除外に含める。
# -----------------------------------------------------------------
locals {
  # 構築ロール ts-030-role-build は必ず除外する。Terraform（role-build で実行）は
  # バケット refresh 時に HeadBucket を呼び、これは s3:ListBucket 権限で評価されるため、
  # フェンスで ListBucket を Deny すると refresh が 403 になりバケットを「削除済み」と誤認する。
  build_role_arn = "arn:aws:iam::${var.aws_account_id}:role/${var.build_role_name}"

  # in の承認 principal（Lambda=conf読取 / EC2=入力取得 / operate=運用 / build=Terraform / admin=緊急）
  in_approved_principals = [
    aws_iam_role.lambda.arn,
    aws_iam_role.ec2.arn,
    aws_iam_role.operate.arn,
    local.build_role_arn,
    "arn:aws:iam::${var.aws_account_id}:user/ts-usr-admin"
  ]
  # out の承認 principal（EC2=結果書込 / operate=運用 / build=Terraform / admin=緊急）。Lambda は除外。
  out_approved_principals = [
    aws_iam_role.ec2.arn,
    aws_iam_role.operate.arn,
    local.build_role_arn,
    "arn:aws:iam::${var.aws_account_id}:user/ts-usr-admin"
  ]
  # フェンスで拒否するデータ操作（管理系は含めない）
  s3_data_actions = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject", "s3:ListBucket"]
}

resource "aws_s3_bucket_policy" "in" {
  bucket = aws_s3_bucket.this["in"].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "DenyNonApprovedDataAccess"
        Effect    = "Deny"
        Principal = "*"
        Action    = local.s3_data_actions
        Resource  = [aws_s3_bucket.this["in"].arn, "${aws_s3_bucket.this["in"].arn}/*"]
        Condition = {
          StringNotLike = { "aws:PrincipalArn" = local.in_approved_principals }
        }
      }
    ]
  })
}

resource "aws_s3_bucket_policy" "out" {
  bucket = aws_s3_bucket.this["out"].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "DenyNonApprovedDataAccess"
        Effect    = "Deny"
        Principal = "*"
        Action    = local.s3_data_actions
        Resource  = [aws_s3_bucket.this["out"].arn, "${aws_s3_bucket.this["out"].arn}/*"]
        Condition = {
          StringNotLike = { "aws:PrincipalArn" = local.out_approved_principals }
        }
      }
    ]
  })
}

# -----------------------------------------------------------------
# Lambda トリガー
#   in バケットへの .conf アップロード（ObjectCreated）で Lambda を起動する。
# -----------------------------------------------------------------

# S3 が Lambda を呼び出す許可（リソースベースポリシー）
resource "aws_lambda_permission" "s3_invoke" {
  statement_id   = "s3-trigger-for-${var.prj_prefix}-lmd-010"
  action         = "lambda:InvokeFunction"
  function_name  = aws_lambda_function.lmd_010.function_name
  principal      = "s3.amazonaws.com"
  source_arn     = aws_s3_bucket.this["in"].arn
  source_account = var.aws_account_id
}

# in バケットのイベント通知設定
resource "aws_s3_bucket_notification" "in" {
  bucket = aws_s3_bucket.this["in"].id

  lambda_function {
    lambda_function_arn = aws_lambda_function.lmd_010.arn
    events              = ["s3:ObjectCreated:*"]
    filter_suffix       = var.s3_notification_suffix
  }

  # 通知作成時点で呼び出し許可が存在する必要があるため明示依存
  depends_on = [aws_lambda_permission.s3_invoke]
}
