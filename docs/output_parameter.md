# `output` ブロック 設定可能キー（Argument Reference）
<!-- Last updated: 2026-09-22 18:05:11（文体を統一） -->

Terraform Language 公式ドキュメント（`developer.hashicorp.com/terraform/language/block/output`）に基づく、`output` ブロックで設定可能なキーの一覧です。AWS プロバイダではなく **Terraform Core 自体の言語機能**である点が、他の `*_parameter.md`（AWS リソース）と異なります。

> 注記: `ephemeral`/`deprecated` は**子モジュールの output のみ**で意味を持ちます（ルートモジュールの output では効果がない）。本プロジェクトの `infra/outputs.tf` はルートモジュールの output のみのため、これらのキーは対象外です。

---

## 1. 設定可能なキー

| キー | 必須/任意 | 型 | 説明 |
|---|---|---|---|
| `value` | **必須** | Expression | モジュールが公開する値。 |
| `type` | 任意 | Type constraint | 出力できる値の型制約。 |
| `description` | 任意 | String | 出力値の説明。`terraform output` 実行時やドキュメント生成で表示されます。 |
| `sensitive` | 任意（既定 `false`） | Boolean | `true` の場合、CLI 出力で値を伏せます（`terraform output` で明示的に参照すれば表示可能）。 |
| `depends_on` | 任意 | List | 暗黙の依存関係だけでは表現できない、明示的な依存リソース/モジュール。 |
| `precondition`（ブロック） | 任意 | Block | 値の算出・state 格納前に検証する事前条件。詳細は下表。 |
| `ephemeral`（子モジュールのみ） | 任意（既定 `false`） | Boolean | `true` の場合、値を state に保存しません。 |
| `deprecated`（子モジュールのみ） | 任意 | String | 非推奨である旨のメッセージ。呼び出し元モジュールでの参照時に警告を表示します。 |

## 2. `precondition` ブロック内部

| キー | 必須/任意 | 説明 |
|---|---|---|
| `condition` | **必須** | `true` を返す必要がある検証式。 |
| `error_message` | **必須** | `condition` が偽の場合に表示するエラーメッセージ。 |

## 3. 重要な注意点

- `sensitive = true` にしても、他の output と同様に state ファイル自体には平文で残ります。
- `depends_on` は基本的に不要です（`value` の式が対象リソースを参照していれば依存関係は自動推論される）。参照を経由しない副作用的な依存がある場合のみ使用します。

## 4. 設定例（参考）

本プロジェクトの `infra/outputs.tf` から抜粋しています（全10出力のうち3つ）。後続タスク（SG・EC2 等）や CLI 確認で参照する ID/ARN を出力します。

```hcl
# VPC ID
output "vpc_id" {
  description = "作成した VPC の ID"
  value       = aws_vpc.main.id
}

# Lambda 実行ロール ARN
output "lambda_role_arn" {
  description = "Lambda 実行ロールの ARN"
  value       = aws_iam_role.lambda.arn
}

# S3 バケット名（in/out）
output "s3_bucket_names" {
  description = "作成した S3 バケット名のマップ"
  value       = { for k, b in aws_s3_bucket.this : k => b.id }
}
```

出力は `infra/outputs.tf` のほか、`infra/backend/outputs.tf`（`tfstate_bucket_name` / `tfstate_bucket_arn`）と `infra/bootstrap/outputs.tf`（`build_role_arn`）にもあります。

本プロジェクトは `description`/`value` のみのシンプルな構成に統一しており、`sensitive`/`precondition`/`depends_on` は現時点では使用していません（出力する値に機密情報を含まないため）。
