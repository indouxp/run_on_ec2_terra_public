# =================================================================
# IAM ロール（WBS 2.4 の一部を先行 / S3 ポリシー・トリガーの依存解消用）
#   Lambda 実行ロール / EC2 実行ロール + Instance Profile
#   オペレーション用ロール（ts-030-role-operate）
# Last updated: 2026-09-22 17:17:45
# =================================================================

# -----------------------------------------------------------------
# Lambda 実行ロール
#   lambda.amazonaws.com が AssumeRole する。S3 起動関数の実行主体。
# -----------------------------------------------------------------
resource "aws_iam_role" "lambda" {
  name        = "${var.prj_prefix}-role-lambda-010"
  description = "Lambda execution role for ${var.prj_prefix} system"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { Service = "lambda.amazonaws.com" }
        Action    = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name = "${var.prj_prefix}-role-lambda-010"
  }
}

# CloudWatch Logs 出力用の AWS 管理ポリシー
resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Lambda ロールのインラインポリシー
#   入力バケット読取 / 出力バケット書込 / EC2 起動系 / EC2ロールへの PassRole /
#   SNS 発行 / SES 送信 を許可する。
resource "aws_iam_role_policy" "lambda" {
  name = "${var.prj_prefix}-lambda-custom-policy-010"
  role = aws_iam_role.lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "s3:GetObject"
        Resource = "arn:aws:s3:::${var.prj_prefix}-bkt-in/*"
      },
      # 注: out への PutObject は付与しない。起動 Lambda は in の .conf を GetObject するのみで
      #     out へは書き込まない（結果を書くのは EC2）。WBS 2.4e の最小権限見直しで削除。
      {
        Effect = "Allow"
        Action = [
          "ec2:RunInstances", "ec2:DescribeInstances", "ec2:DescribeSubnets",
          "ec2:DescribeSecurityGroups", "ec2:CreateTags", "iam:GetInstanceProfile"
        ]
        Resource = "*"
      },
      {
        # running 待ちがタイムアウトしたとき、起動しかけの EC2 を Lambda が削除する
        # （lambda_function.py の terminate_instances）。2.4e で TerminateInstances を削除した際に
        # この経路が AccessDenied になっていた（BUG-006）。自分が起動した EC2 だけに限るため、
        # 起動時に付けるタグ autogen-by=<prj_prefix>-system を条件にする。
        Effect   = "Allow"
        Action   = "ec2:TerminateInstances"
        Resource = "*"
        Condition = {
          StringEquals = { "ec2:ResourceTag/autogen-by" = "${var.prj_prefix}-system" }
        }
      },
      {
        Effect   = "Allow"
        Action   = "iam:PassRole"
        Resource = "arn:aws:iam::${var.aws_account_id}:role/${var.prj_prefix}-role-ec2-010"
      },
      {
        # SMS は電話番号への直接 publish（トピック非経由）で送るため、トピック ARN 単位で
        # 絞ると AccessDenied になる。直接 publish はリソース限定できないため "*"。
        # 参照: infra/lambda/lambda_function.py の sns_client.publish(PhoneNumber=...)
        Effect   = "Allow"
        Action   = "sns:Publish"
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = "ses:SendEmail"
        Resource = "arn:aws:ses:${var.aws_region}:${var.aws_account_id}:identity/*"
      }
    ]
  })
}

# -----------------------------------------------------------------
# EC2 実行ロール
#   ec2.amazonaws.com が AssumeRole する。起動された EC2 の実行主体。
# -----------------------------------------------------------------
resource "aws_iam_role" "ec2" {
  name        = "${var.prj_prefix}-role-ec2-010"
  description = "EC2 execution role for ${var.prj_prefix} system"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { Service = "ec2.amazonaws.com" }
        Action    = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name = "${var.prj_prefix}-role-ec2-010"
  }
}

# CloudWatch エージェント用の AWS 管理ポリシー
resource "aws_iam_role_policy_attachment" "ec2_cwagent" {
  role       = aws_iam_role.ec2.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

# EC2 ロールのインラインポリシー
#   入力バケット読取（Get+List）/ 出力バケット書込（Put）/ SNS / SES / ログ出力。
#   ※ 終了は自己 shutdown（InstanceInitiatedShutdownBehavior=terminate）で行うため
#     TerminateInstances 権限は持たない（WBS 2.4e）。
resource "aws_iam_role_policy" "ec2" {
  name = "${var.prj_prefix}-ec2-custom-policy"
  role = aws_iam_role.ec2.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # in バケット: 入力・run script の取得。--recursive cp のため ListBucket はバケット ARN に対して必要。
      {
        Effect   = "Allow"
        Action   = ["s3:GetObject"]
        Resource = "arn:aws:s3:::${var.prj_prefix}-bkt-in/*"
      },
      {
        Effect   = "Allow"
        Action   = ["s3:ListBucket"]
        Resource = "arn:aws:s3:::${var.prj_prefix}-bkt-in"
      },
      # out バケット: 結果・ログの書き込み（単一ファイル cp のため ListBucket は不要）。
      {
        Effect   = "Allow"
        Action   = ["s3:PutObject"]
        Resource = "arn:aws:s3:::${var.prj_prefix}-bkt-out/*"
      },
      {
        Effect   = "Allow"
        Action   = ["sns:Publish"]
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = ["ses:SendEmail", "ses:SendRawEmail"]
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "arn:aws:logs:${var.aws_region}:*:log-group:${var.prj_prefix}-log-*"
      }
      # 注: ec2:TerminateInstances は付与しない。WBS 2.4c で自己終了化
      #     （InstanceInitiatedShutdownBehavior=terminate）したため、インスタンス内から
      #     terminate API を呼ぶ経路が無くなった（デッド権限のため 2.4e で削除）。
    ]
  })
}

# -----------------------------------------------------------------
# EC2 用 Instance Profile
#   Instance Profile 名は EC2 ロールと同名（Lambda が同名で引いて EC2 に付与する）。
# -----------------------------------------------------------------
resource "aws_iam_instance_profile" "ec2" {
  name = "${var.prj_prefix}-role-ec2-010"
  role = aws_iam_role.ec2.name

  tags = {
    Name = "${var.prj_prefix}-role-ec2-010"
  }
}

# -----------------------------------------------------------------
# オペレーション用ロール（WBS 2.4e で追加）
#   運用者（ts-030-usr-operate）が AssumeRole し、in へのデータ投入/削除・
#   out からの取得/削除を行う。構築権限は一切持たない（最小権限）。
#   信頼するのは ts-030-usr-operate ユーザーのみ（B案：ユーザー ARN を直接信頼）。
#   ※ trust が参照する ts-030-usr-operate はコンソールで先に作成しておくこと
#     （運用ユーザーと再作成手順.md 参照）。
# -----------------------------------------------------------------
resource "aws_iam_role" "operate" {
  name        = "${var.prj_prefix}-role-operate"
  description = "Data operation role for ${var.prj_prefix} (in/out object ops only)"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { AWS = "arn:aws:iam::${var.aws_account_id}:user/${var.prj_prefix}-usr-operate" }
        Action    = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name = "${var.prj_prefix}-role-operate"
  }
}

# オペレーション用ロールのインラインポリシー
#   in: 投入・取得・削除（オブジェクト）＋一覧（バケット）
#   out: 取得・削除（オブジェクト）＋一覧（バケット）。out への書込は EC2 のみ。
resource "aws_iam_role_policy" "operate" {
  name = "${var.prj_prefix}-operate-policy"
  role = aws_iam_role.operate.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "InObjectOps"
        Effect   = "Allow"
        Action   = ["s3:PutObject", "s3:GetObject", "s3:DeleteObject"]
        Resource = "arn:aws:s3:::${var.prj_prefix}-bkt-in/*"
      },
      {
        Sid      = "InListBucket"
        Effect   = "Allow"
        Action   = ["s3:ListBucket"]
        Resource = "arn:aws:s3:::${var.prj_prefix}-bkt-in"
      },
      {
        Sid      = "OutObjectOps"
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:DeleteObject"]
        Resource = "arn:aws:s3:::${var.prj_prefix}-bkt-out/*"
      },
      {
        Sid      = "OutListBucket"
        Effect   = "Allow"
        Action   = ["s3:ListBucket"]
        Resource = "arn:aws:s3:::${var.prj_prefix}-bkt-out"
      }
    ]
  })
}
