# Lambda 関連リソース 設定可能キー（Argument Reference）
<!-- Last updated: 2026-09-22 18:05:23（設定例のコメントをコードに合わせ、文体を統一） -->

Terraform AWS Provider（本プロジェクトの固定バージョン `~> 5.0`、`.terraform.lock.hcl` 上の実バージョン `5.100.0`）および `hashicorp/archive` プロバイダ（固定バージョン `~> 2.0`、実バージョン `2.8.0`）の公式ドキュメントに基づく、Lambda 関連リソースで設定可能なキー（引数）の一覧です。

本プロジェクトでは、以下を組み合わせて起動 Lambda 関数を構成します（`infra/compute.tf`, `infra/storage.tf`）。

- `data "archive_file"` … デプロイパッケージ（zip）の作成
- `aws_lambda_function` … Lambda 関数本体
- `aws_lambda_permission` … S3 から Lambda を呼び出す許可（`infra/storage.tf` 側で定義）

> 注記: 本一覧は **AWS Provider 最新版**の Argument Reference に基づいています。調査時点で開発版（次期リリース）にのみ存在が確認され、本プロジェクトの固定バージョンでの対応が未確認の項目（`capacity_provider_config`、`durable_config`、`tenancy_config` 等の新しい実行モデル関連引数）は本一覧には含めていません。

---

## 1. `data "archive_file"`（デプロイパッケージの zip 化）

| キー | 必須/任意 | 説明 |
|---|---|---|
| `type` | **必須** | 生成するアーカイブ種別。`zip` または `tar.gz`。 |
| `output_path` | **必須** | 出力ファイルのパス。 |
| `source_dir` | 排他選択1 | ディレクトリ全体をアーカイブ対象にします（本プロジェクトで使用）。 |
| `source_file` | 排他選択1 | 単一ファイルをアーカイブ対象にします。 |
| `source_content` + `source_content_filename` | 排他選択1 | 文字列コンテンツを指定ファイル名でアーカイブに追加。 |
| `source`（ブロック・複数可） | 排他選択1 | `content`（必須）/`filename`（必須）で複数ファイルを個別指定。 |
| `excludes` | 任意 | `source_dir` 使用時に除外するパスの集合（glob 対応）。 |
| `exclude_symlink_directories` | 任意（既定 `false`） | シンボリックリンクディレクトリを除外するか。 |
| `output_file_mode` | 任意 | アーカイブ内全ファイルの八進数パーミッション文字列（例 `"0666"`）。クロスプラットフォームでのハッシュ再現性確保に有用。 |

> `source_dir` / `source_file` / `source_content`+`source_content_filename` / `source` のうち**いずれか1つのみ**を指定します（排他）。

### Attribute（参照のみ・設定不可）

| Attribute | 説明 |
|---|---|
| `id` | 出力ファイルの SHA1 チェックサム。 |
| `output_size` | 出力アーカイブのバイトサイズ。 |
| `output_md5` / `output_sha` / `output_sha256` / `output_sha512` | 各ハッシュ値。 |
| `output_base64sha256` | Base64 エンコードされた SHA256（`aws_lambda_function.source_code_hash` に渡します。本プロジェクトで使用）。 |
| `output_base64sha512` | Base64 エンコードされた SHA512。 |

> アーカイブは `terraform plan` 実行時に生成されます。CI 等で `plan` と `apply` の実行環境が分かれ zip を永続化できない場合は、データソース版ではなく `archive_file` **リソース**版の使用が公式に推奨されています。

---

## 2. `aws_lambda_function`

### 2-1. 主な引数

| キー | 必須/任意 | 説明 |
|---|---|---|
| `function_name` | **必須** | Lambda 関数名（一意）。 |
| `role` | **必須** | 実行ロールの ARN。 |
| `filename` | 排他選択1 | ローカルのデプロイパッケージ（zip）パス（本プロジェクトで使用）。 |
| `s3_bucket` + `s3_key` | 排他選択1 | S3 上のデプロイパッケージを参照。 |
| `image_uri` | 排他選択1 | コンテナイメージ（ECR）の URI。 |
| `s3_object_version` | 任意 | `s3_bucket` 使用時、対象オブジェクトのバージョン。 |
| `handler` | 条件付き必須 | エントリポイント。`package_type = Zip` の場合必須。 |
| `runtime` | 条件付き必須 | ランタイム識別子（例 `python3.12`）。`package_type = Zip` の場合必須。 |
| `package_type` | 任意（既定 `Zip`） | `Zip` または `Image`。 |
| `architectures` | 任意（既定 `["x86_64"]`） | `["x86_64"]` または `["arm64"]`。 |
| `memory_size` | 任意（既定 128） | メモリ MB（128〜10,240）。 |
| `timeout` | 任意（既定 3秒） | 実行タイムアウト秒（1〜900）。 |
| `ephemeral_storage.size` | 任意（既定 512） | `/tmp` 容量 MB（512〜10,240）。 |
| `reserved_concurrent_executions` | 任意（既定 `-1`＝無制限） | 予約同時実行数。`0` はトリガー無効化と同じ効果です。 |
| `publish` | 任意（既定 `false`） | `true` で新バージョンを発行。 |
| `layers` | 任意 | Lambda Layer ARN のリスト（最大5）。 |
| `source_code_hash` | 任意 | ユーザー定義のソースハッシュ（ローカル変更検知用。本プロジェクトは `archive_file.output_base64sha256` を使用）。 |
| `kms_key_arn` | 任意 | 環境変数暗号化用 KMS キー ARN。 |
| `code_signing_config_arn` | 任意 | コード署名設定の ARN。 |
| `description` | 任意 | 関数の説明。 |
| `dead_letter_config.target_arn` | 任意 | 失敗時の通知先（SNS/SQS）ARN。 |
| `environment.variables` | 任意 | 環境変数のマップ。 |
| `vpc_config` | 任意 | `subnet_ids`（必須）/`security_group_ids`（必須）で VPC 内実行を指定。 |
| `file_system_config` | 任意 | EFS マウント設定（`arn`/`local_mount_path`）。 |
| `image_config` | 任意 | コンテナイメージの `command`/`entry_point`/`working_directory`。 |
| `tracing_config.mode` | 任意 | X-Ray トレーシング。`Active`/`PassThrough`。 |
| `logging_config` | 任意 | `log_format`（`Text`/`JSON`）、`application_log_level`/`system_log_level`/`log_group`。本プロジェクトは未指定。このため関数のログは Lambda 既定の `/aws/lambda/ts-030-lmd-010`（Terraform 管理外）に出力され、`monitoring.tf` の `ts-030-log-lambda-010` とそのメトリクスフィルタは使われていません（改善対象 B-6）。 |
| `tags` | 任意 | タグのマップ。 |

### 2-2. Attribute（参照のみ・設定不可）

| Attribute | 説明 |
|---|---|
| `arn` | 関数の ARN。`aws_lambda_permission` の `function_name` 等から参照。 |
| `qualified_arn` | バージョン込みの ARN（`publish=true` 時）。 |
| `invoke_arn` | API Gateway 統合用の invoke ARN。 |
| `version` | 最新発行バージョン。 |
| `last_modified` | 最終更新日時。 |
| `source_code_size` | デプロイパッケージのバイトサイズ。 |
| `tags_all` | `default_tags` を含む全タグ。 |

### 2-3. 特記事項

- `filename` / `s3_bucket` / `image_uri` は排他です。本プロジェクトは `filename` + `source_code_hash` の組み合わせです。
- `source_code_hash`（ローカル変更検知用）と `code_sha256`（AWS 側実値との照合、参照専用属性）は役割が異なります。本プロジェクトは前者を明示指定し、`data.archive_file` のハッシュ変化時のみ再デプロイされるようにしています。
- VPC 接続の Lambda は ENI 削除に時間がかかるため `timeouts { delete = "45m" }` の指定が推奨される場合があります（本プロジェクトは VPC 未接続のため該当なし）。

---

## 3. `aws_lambda_permission`（S3 等からの呼び出し許可）

| キー | 必須/任意 | 説明 |
|---|---|---|
| `action` | **必須** | 許可するアクション（例 `lambda:InvokeFunction`）。 |
| `function_name` | **必須** | 対象 Lambda 関数の名前または ARN。 |
| `principal` | **必須** | 呼び出しを許可する AWS サービスまたはアカウント（例 `s3.amazonaws.com`）。 |
| `statement_id` | 任意 | ステートメント識別子。省略時は Terraform が自動生成。 |
| `statement_id_prefix` | 任意 | ステートメント識別子のプレフィックス。`statement_id` と排他。 |
| `qualifier` | 任意 | 対象とする関数のバージョンまたはエイリアス名。 |
| `source_account` | 任意 | クロスアカウント／S3／SES 等での送信元アカウント ID。 |
| `source_arn` | 任意 | 呼び出し元リソースの ARN（例：S3 バケットの ARN）。 |
| `principal_org_id` | 任意 | AWS Organizations の組織 ID。組織配下の全アカウントに許可。 |
| `event_source_token` | 任意 | Alexa Skills 用のイベントソーストークン。 |
| `function_url_auth_type` | 任意 | Function URL の認証方式（`AWS_IAM`/`NONE`）。 |

### Attribute
このリソース固有の参照専用属性はありません（`id` 等の暗黙属性のみ）。

> Lambda リソースベースポリシーであり、Lambda **実行ロール**（`aws_iam_role`）とは別物です（「誰が呼べるか」と「実行時に何ができるか」の違い）。詳細は [用語一覧.md](用語一覧.md) を参照。

---

## 4. 設定例（参考）

本プロジェクトの `infra/compute.tf` と `infra/storage.tf` の該当部分です。コメントは説明用に1行へまとめています。

```hcl
# 説明用: デプロイパッケージの zip 化（infra/lambda/ 配下をまとめる）
data "archive_file" "lambda" {
  type        = "zip"
  source_dir  = "${path.module}/lambda"
  output_path = "${path.module}/build/lambda.zip"
}

# 説明用: Lambda 起動関数（S3 の .conf アップロードをトリガーに EC2 を起動）
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

# 説明用: S3 が Lambda を呼び出す許可（infra/storage.tf）
resource "aws_lambda_permission" "s3_invoke" {
  statement_id   = "s3-trigger-for-${var.prj_prefix}-lmd-010"
  action         = "lambda:InvokeFunction"
  function_name  = aws_lambda_function.lmd_010.function_name
  principal      = "s3.amazonaws.com"
  source_arn     = aws_s3_bucket.this["in"].arn
  source_account = var.aws_account_id
}
```
