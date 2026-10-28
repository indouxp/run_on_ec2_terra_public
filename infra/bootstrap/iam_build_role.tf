# =================================================================
# 構築用 IAM ロール ts-030-role-build
#   infra/ の terraform plan/apply/destroy を実行する主体
#
#   - Trust Policy: アカウントルートを信頼（実際に AssumeRole できるかは
#     呼び出し側プリンシパルの権限で制御する。管理者 ts-usr-admin は可）。
#   - 権限: 6サービス限定（原則 Resource:*）。Administrator より絞る。
#     EventBridge（終了は EC2 の自己 terminate で行うため不要）と
#     SNS トピック管理（SMS は電話番号へ直接 publish のためトピック不要）は
#     含めない。SMS 送信の sns:Publish は Lambda/EC2 の実行ロール
#     （infra/iam.tf）側にある。
# Last updated: 2026-09-22 17:18:05
# =================================================================

# 実行中のアカウント ID を取得（Trust Policy のルート ARN 構築に使う）
data "aws_caller_identity" "current" {}

# 構築用ロール本体
resource "aws_iam_role" "build" {
  name        = "${var.prj_prefix}-role-build"
  description = "Infrastructure Build Role for ${var.prj_prefix}"

  # 信頼ポリシー（誰がこのロールを AssumeRole(引き受ける) できるか）
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root" }
        Action    = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name = "${var.prj_prefix}-role-build"
  }
}

# 構築権限ポリシー（インラインポリシー）
resource "aws_iam_role_policy" "build" {
  name = "${var.prj_prefix}-role-build-policy"
  role = aws_iam_role.build.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "IAMManagement"
        Effect = "Allow"
        Action = [
          "iam:CreateRole", "iam:DeleteRole", "iam:GetRole", "iam:ListRoles", "iam:PassRole",
          "iam:CreatePolicy", "iam:DeletePolicy", "iam:GetPolicy", "iam:ListPolicies",
          "iam:AttachRolePolicy", "iam:DetachRolePolicy", "iam:PutRolePolicy", "iam:DeleteRolePolicy",
          "iam:GetRolePolicy",
          "iam:CreateInstanceProfile", "iam:DeleteInstanceProfile", "iam:GetInstanceProfile",
          "iam:AddRoleToInstanceProfile", "iam:RemoveRoleFromInstanceProfile",
          "iam:ListInstanceProfiles", "iam:ListRolePolicies", "iam:ListAttachedRolePolicies",
          # ロール削除前に Terraform が紐づく Instance Profile を確認するため必要（BUG-004）
          "iam:ListInstanceProfilesForRole",
          "iam:TagRole", "iam:UntagRole",
          "iam:TagInstanceProfile", "iam:UntagInstanceProfile",
          "iam:TagUser", "iam:UntagUser"
        ]
        Resource = "*"
      },
      {
        Sid    = "EC2VPCManagement"
        Effect = "Allow"
        Action = [
          "ec2:CreateVpc", "ec2:DeleteVpc", "ec2:DescribeVpcs", "ec2:ModifyVpcAttribute", "ec2:DescribeVpcAttribute",
          "ec2:CreateSubnet", "ec2:DeleteSubnet", "ec2:DescribeSubnets", "ec2:ModifySubnetAttribute",
          "ec2:DescribeNetworkInterfaces", "ec2:DetachNetworkInterface", "ec2:DeleteNetworkInterface",
          "ec2:CreateInternetGateway", "ec2:DeleteInternetGateway", "ec2:DescribeInternetGateways",
          "ec2:AttachInternetGateway", "ec2:DetachInternetGateway",
          "ec2:CreateRouteTable", "ec2:DeleteRouteTable", "ec2:DescribeRouteTables",
          "ec2:CreateRoute", "ec2:DeleteRoute", "ec2:AssociateRouteTable", "ec2:DisassociateRouteTable",
          "ec2:CreateSecurityGroup", "ec2:DeleteSecurityGroup", "ec2:DescribeSecurityGroups",
          "ec2:DescribeSecurityGroupRules",
          "ec2:AuthorizeSecurityGroupIngress", "ec2:RevokeSecurityGroupIngress",
          "ec2:AuthorizeSecurityGroupEgress", "ec2:RevokeSecurityGroupEgress",
          "ec2:CreateKeyPair", "ec2:DeleteKeyPair", "ec2:DescribeKeyPairs",
          "ec2:RunInstances", "ec2:TerminateInstances", "ec2:DescribeInstances",
          "ec2:CreateTags", "ec2:DeleteTags"
        ]
        Resource = "*"
      },
      {
        Sid    = "S3Management"
        Effect = "Allow"
        Action = [
          "s3:CreateBucket", "s3:DeleteBucket", "s3:ListBucket", "s3:ListAllMyBuckets", "s3:GetBucketLocation",
          "s3:PutBucketPolicy", "s3:GetBucketPolicy", "s3:DeleteBucketPolicy",
          "s3:PutBucketPublicAccessBlock", "s3:GetBucketPublicAccessBlock",
          "s3:PutEncryptionConfiguration", "s3:GetEncryptionConfiguration",
          "s3:PutBucketVersioning", "s3:GetBucketVersioning",
          "s3:ListBucketVersions", "s3:DeleteObjectVersion",
          "s3:PutLifecycleConfiguration", "s3:GetLifecycleConfiguration",
          "s3:PutBucketNotification", "s3:GetBucketNotification",
          "s3:PutBucketOwnershipControls", "s3:GetBucketOwnershipControls",
          "s3:PutBucketTagging", "s3:GetBucketTagging",
          # Terraform の aws_s3_bucket は作成後に多数の GetBucket* を read-after-write
          # で呼ぶため、設定する項目以外の読み取り権限も必要（いずれも読み取り専用）
          "s3:GetBucketAcl", "s3:GetBucketCORS", "s3:GetBucketWebsite",
          "s3:GetAccelerateConfiguration", "s3:GetBucketRequestPayment",
          "s3:GetBucketLogging", "s3:GetReplicationConfiguration",
          "s3:GetBucketObjectLockConfiguration"
        ]
        Resource = "*"
      },
      {
        # force_destroy でバケットを空にする際、バージョニング無効バケットの
        # オブジェクト（version=null）削除は s3:DeleteObject で評価される（BUG-004）。
        # データ削除権限のため、本プロジェクトのバケット内オブジェクトに限定する。
        Sid      = "S3EmptyProjectBuckets"
        Effect   = "Allow"
        Action   = "s3:DeleteObject"
        Resource = "arn:aws:s3:::${var.prj_prefix}-*/*"
      },
      {
        # infra の state を S3 バックエンド（infra/backend/ で作成）で読み書きする。
        # ロックファイル（.tflock）の削除は上の S3EmptyProjectBuckets の DeleteObject で足りる。
        Sid      = "S3TerraformState"
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:PutObject"]
        Resource = "arn:aws:s3:::${var.prj_prefix}-bkt-tfstate/*"
      },
      {
        # state の旧世代（バージョン）は構築ロールから消させない。
        # S3Management の DeleteObjectVersion（Resource "*"）より明示的 Deny が優先する。
        Sid      = "DenyStateHistoryDeletion"
        Effect   = "Deny"
        Action   = "s3:DeleteObjectVersion"
        Resource = "arn:aws:s3:::${var.prj_prefix}-bkt-tfstate/*"
      },
      {
        Sid    = "LambdaManagement"
        Effect = "Allow"
        Action = [
          "lambda:CreateFunction", "lambda:DeleteFunction", "lambda:GetFunction",
          "lambda:GetFunctionConfiguration", "lambda:GetFunctionCodeSigningConfig",
          "lambda:ListVersionsByFunction", "lambda:GetRuntimeManagementConfig",
          "lambda:UpdateFunctionCode", "lambda:UpdateFunctionConfiguration",
          "lambda:AddPermission", "lambda:RemovePermission", "lambda:GetPolicy",
          "lambda:ListFunctions", "lambda:ListTags", "lambda:TagResource"
        ]
        Resource = "*"
      },
      {
        Sid    = "CloudWatchLogsManagement"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup", "logs:DeleteLogGroup", "logs:DescribeLogGroups",
          "logs:PutRetentionPolicy", "logs:DeleteLogStream", "logs:DescribeLogStreams",
          "logs:TagLogGroup", "logs:PutMetricFilter", "logs:DeleteMetricFilter",
          "logs:DescribeMetricFilters",
          # Terraform（provider v5）の aws_cloudwatch_log_group はタグを ARN ベース API で
          # 読み書きするため以下を追加（WBS 2.8）。
          "logs:ListTagsForResource", "logs:TagResource", "logs:UntagResource"
        ]
        Resource = "*"
      },
      {
        Sid    = "CloudTrailManagement"
        Effect = "Allow"
        Action = [
          "cloudtrail:CreateTrail", "cloudtrail:DeleteTrail", "cloudtrail:DescribeTrails",
          "cloudtrail:GetTrail", "cloudtrail:StartLogging", "cloudtrail:StopLogging",
          "cloudtrail:PutEventSelectors", "cloudtrail:AddTags",
          # Terraform の aws_cloudtrail は refresh/更新で以下の read/update を呼ぶため追加（WBS 2.8）。
          "cloudtrail:UpdateTrail", "cloudtrail:RemoveTags",
          "cloudtrail:GetTrailStatus", "cloudtrail:GetEventSelectors",
          "cloudtrail:GetInsightSelectors", "cloudtrail:ListTags"
        ]
        Resource = "*"
      },
      {
        Sid      = "STSUtils"
        Effect   = "Allow"
        Action   = ["sts:GetCallerIdentity"]
        Resource = "*"
      }
    ]
  })
}
