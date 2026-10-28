# =================================================================
# コンピュート（WBS 2.5 の一部を先行 / S3 トリガーの依存解消用）
#   Lambda 起動関数 ts-030-lmd-010
#   ソース: infra/lambda/（lambda_function.py / user_data_template.sh）
# Last updated: 2026-09-22 17:17:32
# =================================================================

# -----------------------------------------------------------------
# デプロイパッケージの zip 化
#   infra/lambda/ 配下（lambda_function.py と user_data_template.sh）を
#   まとめて zip 化する。テンプレートは実体ファイルとして同梱する。
# -----------------------------------------------------------------
data "archive_file" "lambda" {
  type        = "zip"
  source_dir  = "${path.module}/lambda"
  output_path = "${path.module}/build/lambda.zip"
}

# -----------------------------------------------------------------
# Lambda 起動関数
#   S3 の .conf アップロードをトリガーに EC2 を起動する関数。
#   環境変数 / VPC 設定 / レイヤーは無し。
# -----------------------------------------------------------------
resource "aws_lambda_function" "lmd_010" {
  function_name = "${var.prj_prefix}-lmd-010"
  description   = "S3 event trigger to run EC2 instance"
  role          = aws_iam_role.lambda.arn

  runtime     = "python3.12"
  handler     = "lambda_function.main_handler"
  timeout     = 300
  memory_size = 256

  filename         = data.archive_file.lambda.output_path
  source_code_hash = data.archive_file.lambda.output_base64sha256

  tags = {
    Name = "${var.prj_prefix}-lmd-010"
  }
}
