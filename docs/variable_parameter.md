# `variable` ブロック 設定可能キー（Argument Reference）
<!-- Last updated: 2026-09-22 18:05:11（設定例のコメントをコードに合わせ、文体を統一） -->

Terraform Language 公式ドキュメント（`developer.hashicorp.com/terraform/language/block/variable`）に基づく、`variable` ブロックで設定可能なキーの一覧です。AWS プロバイダではなく **Terraform Core 自体の言語機能**である点が、他の `*_parameter.md`（AWS リソース）と異なります。

> 注記: 本一覧は Terraform 言語の最新版ドキュメントに基づいています。`const`/`deprecated`/`ephemeral` 等は比較的新しい追加キーのため、`required_version` で許容する Terraform CLI バージョンによっては使用できない場合があります（本プロジェクトの `required_version` は `infra/`・`infra/backend/` が `">= 1.10"`、`infra/bootstrap/` が `">= 1.0"`。使用中の CLI は 1.16.3。実際に使う際はインストール済み CLI バージョンとの整合性を確認してください）。

> 注記: `terraform {}` 内の `backend` ブロックでは変数（`var.*`）を参照できません。そのため `infra/provider.tf` の `backend "s3"` はバケット名・プロファイル・ロール ARN を直書きしています（[provider_parameter.md](provider_parameter.md) 参照）。

---

## 1. 設定可能なキー

| キー | 必須/任意 | 型 | 説明 |
|---|---|---|---|
| `type` | 任意 | Type constraint | 値の型制約。未指定時は任意の型を受け付けます。 |
| `default` | 任意 | Expression（リテラルのみ） | デフォルト値。呼び出し側で値を渡さない場合に使用されます。 |
| `description` | 任意 | String | 変数の目的・期待する値の説明。`terraform plan`/ドキュメント生成で表示されます。 |
| `validation`（ブロック・複数可） | 任意 | Block | カスタム検証規則。詳細は下表。 |
| `sensitive` | 任意（既定 `false`） | Boolean | `true` の場合、CLI 出力（plan/apply のログ）で値を伏せます。 |
| `nullable` | 任意（既定 `true`） | Boolean | `false` の場合、呼び出し側から `null` を渡すことを禁止します。 |
| `ephemeral` | 任意（既定 `false`） | Boolean | `true` の場合、値を state/plan ファイルに保存しません（一時的な認証情報等に使用）。 |
| `const` | 任意（既定 `false`） | Boolean | `true` の場合、`terraform init` 等の設定読み込みの早い段階で値を確定させる必要がある変数として扱います。 |
| `deprecated` | 任意 | String | 非推奨である旨のメッセージ。ルートモジュールでの指定時・子モジュール呼び出し時に警告を表示します。 |

## 2. `validation` ブロック内部

| キー | 必須/任意 | 説明 |
|---|---|---|
| `condition` | **必須** | `true` を返す必要がある検証式（変数自身を参照可能）。 |
| `error_message` | **必須** | `condition` が偽の場合に表示するエラーメッセージ。 |

## 3. 型制約（Type Constraint）の書き方

- 基本型: `string` / `number` / `bool` / `any`
- 複合型: `list(<型>)` / `set(<型>)` / `map(<型>)` / `object({ ... })` / `tuple([<型>, ...])`
- `object({...})` 内では `optional(<型>, <デフォルト値>)` を使うと任意属性を定義できます。

## 4. 重要な注意点

- `default` に指定できるのは**リテラル値**のみで、他の変数やリソース属性を参照する式は書けません。
- `sensitive = true` にしても state ファイル自体には平文で残ります（state の暗号化・アクセス制御は別途必要）。
- `nullable = false` は、呼び出し側が明示的に `null` を渡すケースを防ぎたい場合に指定します（`default` の有無とは独立した設定）。

## 5. 設定例（参考）

本プロジェクトの `infra/variables.tf` から抜粋しています（全11変数のうち3つ）。

```hcl
# AWS リージョン
variable "aws_region" {
  description = "リソースを作成する AWS リージョン"
  type        = string
  default     = "ap-northeast-1"
}

# AWS アカウント ID（AssumeRole 対象ロールの ARN 構築に使用）
variable "aws_account_id" {
  description = "リソースを作成する AWS アカウント ID"
  type        = string
  # （説明用コメント）default なし＝呼び出し側（terraform.tfvars）での指定が必須
}

# S3 ライフサイクルでオブジェクトを削除するまでの日数（in/out 共通）
#   入出力ファイルは一時的なデータのため、既定 30 日で自動削除する
variable "s3_expire_days" {
  description = "S3 バケットのオブジェクトを削除するまでの日数"
  type        = number
  default     = 30
}
```

本プロジェクトは `validation`/`sensitive`/`nullable`/`ephemeral`/`const`/`deprecated` を現時点では使用せず、`description`/`type`/`default` のみのシンプルな構成に統一しています（`aws_account_id` のように既定値を持たせたくない変数は `default` を省略）。`infra/backend/`・`infra/bootstrap/` にも同じ形式の variables.tf があります（backend は `noncurrent_days = 90`、bootstrap は `role_admin_profile = "ts-030-usr-role-admin"` を持つ）。
