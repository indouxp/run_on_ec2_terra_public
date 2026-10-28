# =================================================================
# Terraform state 用 S3 バケット（改善対象 B-5）
#   infra/ の state を置くリモートバックエンド。旧端末のディスク故障で
#   ローカル state を消失した事故（BUG-003）の再発防止。
#   - infra / bootstrap の全削除・再構築サイクルの対象外（常設）
#   - prevent_destroy で Terraform からの誤削除を防ぐ
#   - バージョニングで state の旧世代を残し、誤更新から戻せるようにする
#   - ロックは infra 側 backend の use_lockfile（.tflock オブジェクト）で行う
# Last updated: 2026-09-22 01:46:37
# =================================================================

# バケット本体（force_destroy は付けない：中身ごと消えると復旧できないため）
resource "aws_s3_bucket" "tfstate" {
  bucket = "${var.prj_prefix}-bkt-tfstate"

  tags = {
    Name = "${var.prj_prefix}-bkt-tfstate"
  }

  lifecycle {
    prevent_destroy = true
  }
}

# バージョニング（state の旧世代を保持）
resource "aws_s3_bucket_versioning" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  versioning_configuration {
    status = "Enabled"
  }
}

# パブリックアクセスブロック（4項目すべて有効）
resource "aws_s3_bucket_public_access_block" "tfstate" {
  bucket                  = aws_s3_bucket.tfstate.id
  block_public_acls       = true
  ignore_public_acls      = true
  block_public_policy     = true
  restrict_public_buckets = true
}

# 既定の暗号化（SSE-S3 / AES256 + バケットキー有効。infra の in/out と同じ）
resource "aws_s3_bucket_server_side_encryption_configuration" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

# 所有者制御（ACL 無効化 / BucketOwnerEnforced）
resource "aws_s3_bucket_ownership_controls" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

# ライフサイクル（旧バージョンのみ N 日で削除。現行 state は削除しない）
#   バージョニング設定の後に適用する必要があるため depends_on を付ける
resource "aws_s3_bucket_lifecycle_configuration" "tfstate" {
  bucket     = aws_s3_bucket.tfstate.id
  depends_on = [aws_s3_bucket_versioning.tfstate]

  rule {
    id     = "${aws_s3_bucket.tfstate.bucket}-noncurrent-${var.noncurrent_days}d"
    status = "Enabled"

    filter {} # バケット全体

    noncurrent_version_expiration {
      noncurrent_days = var.noncurrent_days
    }
  }
}

# バケットポリシー（TLS 以外のアクセスを全面拒否）
resource "aws_s3_bucket_policy" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  # PAB 適用後にポリシーを設定する（競合による失敗を避ける）
  depends_on = [aws_s3_bucket_public_access_block.tfstate]

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "DenyInsecureTransport"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource = [
          aws_s3_bucket.tfstate.arn,
          "${aws_s3_bucket.tfstate.arn}/*"
        ]
        Condition = {
          Bool = { "aws:SecureTransport" = "false" }
        }
      }
    ]
  })
}
