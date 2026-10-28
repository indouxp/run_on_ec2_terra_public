# =================================================================
# 監視・通知（WBS 2.8）
#   CloudWatch Logs（ロググループ3種＋メトリクスフィルタ3種）と
#   CloudTrail（証跡＋ログ用 S3 バケット＋バケットポリシー）を作成する。
#
#   方針（本プロジェクトの決定事項）:
#   - SNS トピック/サブスクリプションは作らない。SMS は電話番号への直接
#     publish、メールは SES 直接送信で、トピックは実行時に使われないため。
#   - CloudWatch アラームは作らない。
#   - CloudWatch Logs の KMS 暗号化（改善 S-1）は不要と判断（機微な通知でないため）。
# Last updated: 2026-09-22 17:17:55
# =================================================================

# -----------------------------------------------------------------
# CloudWatch Logs
#   lambda / ec2 / system の3ロググループと、各グループの "ERROR" 検知
#   メトリクスフィルタを for_each でまとめて生成する。
# -----------------------------------------------------------------
locals {
  # ロググループとメトリクスフィルタの共通定義。
  #   key       : リソースキー兼メトリクス種別（lambda/ec2/system）
  #   log_suffix: ロググループ名の中間語（${prj}-log-<suffix>-010）
  #   namespace : メトリクス名前空間の末尾（${prj}/<namespace>）
  cw_targets = {
    lambda = { log_suffix = "lambda", namespace = "Lambda" }
    ec2    = { log_suffix = "ec2", namespace = "EC2" }
    system = { log_suffix = "system", namespace = "System" }
  }
}

# ロググループ3種（保持30日）。
#   KMS は付けない（S-1 は不要と判断）。Project タグは default_tags で付与。
resource "aws_cloudwatch_log_group" "this" {
  for_each = local.cw_targets

  name              = "${var.prj_prefix}-log-${each.value.log_suffix}-010"
  retention_in_days = 30

  tags = {
    Name      = "${var.prj_prefix}-log-${each.value.log_suffix}-010"
    Component = each.key
  }
}

# メトリクスフィルタ3種（"ERROR" 出現を metricValue=1 で計上）。
resource "aws_cloudwatch_log_metric_filter" "error" {
  for_each = local.cw_targets

  name           = "${var.prj_prefix}-${each.key}-error-filter"
  log_group_name = aws_cloudwatch_log_group.this[each.key].name
  pattern        = "ERROR"

  metric_transformation {
    name      = "${var.prj_prefix}-${each.key}-errors"
    namespace = "${var.prj_prefix}/${each.value.namespace}"
    value     = "1"
  }
}

# -----------------------------------------------------------------
# CloudTrail 用ログバケット
#   in/out バケット（storage.tf）と同等のハードニングを施す。
# -----------------------------------------------------------------
resource "aws_s3_bucket" "cloudtrail" {
  bucket = "${var.prj_prefix}-bkt-cloudtrail-logs"

  # destroy 時にログオブジェクト（全バージョン）ごと削除する。
  # 証跡は常時ログを書き込むため、無いと BucketNotEmpty で destroy が失敗する。
  # 注意: terraform destroy で監査ログも消える。
  force_destroy = true

  tags = {
    Name = "${var.prj_prefix}-bkt-cloudtrail-logs"
  }
}

# パブリックアクセスブロック（4項目すべて有効）。
resource "aws_s3_bucket_public_access_block" "cloudtrail" {
  bucket                  = aws_s3_bucket.cloudtrail.id
  block_public_acls       = true
  ignore_public_acls      = true
  block_public_policy     = true
  restrict_public_buckets = true
}

# 既定の暗号化（SSE-S3 / AES256 + バケットキー有効）。CloudTrail の KMS は使わない。
resource "aws_s3_bucket_server_side_encryption_configuration" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

# 所有者制御（ACL 無効化 / BucketOwnerEnforced）。
#   CloudTrail は PutObject 時に canned ACL "bucket-owner-full-control" を送るが、
#   BucketOwnerEnforced でもこの値だけは許容されるため配信は成立する。
resource "aws_s3_bucket_ownership_controls" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

# CloudTrail サービスへの配信許可ポリシー。
#   - AclCheck: cloudtrail が s3:GetBucketAcl を実行できるようにする。
#   - Write   : AWSLogs/<account>/* への s3:PutObject を許可。
#   s3:x-amz-acl 条件に加え、aws:SourceArn（当該トレイル限定）を付与して
#   混同代理（confused deputy）を防ぐ。SourceArn は依存循環を避けるため文字列で組み立てる。
locals {
  cloudtrail_arn = "arn:aws:cloudtrail:${var.aws_region}:${var.aws_account_id}:trail/${var.prj_prefix}-trail-010"
}

resource "aws_s3_bucket_policy" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AWSCloudTrailAclCheck"
        Effect    = "Allow"
        Principal = { Service = "cloudtrail.amazonaws.com" }
        Action    = "s3:GetBucketAcl"
        Resource  = aws_s3_bucket.cloudtrail.arn
        Condition = {
          StringEquals = { "aws:SourceArn" = local.cloudtrail_arn }
        }
      },
      {
        Sid       = "AWSCloudTrailWrite"
        Effect    = "Allow"
        Principal = { Service = "cloudtrail.amazonaws.com" }
        Action    = "s3:PutObject"
        Resource  = "${aws_s3_bucket.cloudtrail.arn}/AWSLogs/${var.aws_account_id}/*"
        Condition = {
          StringEquals = {
            "s3:x-amz-acl"  = "bucket-owner-full-control"
            "aws:SourceArn" = local.cloudtrail_arn
          }
        }
      }
    ]
  })
}

# -----------------------------------------------------------------
# CloudTrail 証跡
#   マルチリージョン＋グローバルサービスイベント有効。ログ検証・KMS は無し。
#   全 S3 バケットのオブジェクトレベル（データ）イベントを記録する。
# -----------------------------------------------------------------
resource "aws_cloudtrail" "this" {
  name           = "${var.prj_prefix}-trail-010"
  s3_bucket_name = aws_s3_bucket.cloudtrail.id

  is_multi_region_trail         = true
  include_global_service_events = true
  enable_logging                = true

  event_selector {
    read_write_type           = "All"
    include_management_events = true

    data_resource {
      type   = "AWS::S3::Object"
      values = ["arn:aws:s3:::"]
    }
  }

  tags = {
    Name = "${var.prj_prefix}-trail-010"
  }

  # バケットポリシーが無いと create-trail が失敗するため明示依存。
  depends_on = [aws_s3_bucket_policy.cloudtrail]
}
