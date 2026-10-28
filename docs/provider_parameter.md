# `terraform` / `provider` ブロック 設定可能キー（Argument Reference）
<!-- Last updated: 2026-10-29 08:50:18（公開版向けに、公開版に含めない実行ログへのリンクを外す） -->

Terraform Language 公式ドキュメント（`developer.hashicorp.com/terraform/language/block/terraform`, `.../providers/configuration`）および AWS Provider 公式ドキュメントに基づく、`terraform` ブロックと `provider "aws"` ブロックで設定可能なキーの一覧です。前者は Terraform Core 自体の言語機能、後者は Core 共通部分＋AWS プロバイダ固有部分で構成されます。

---

## 1. `terraform` ブロック

| キー | 必須/任意 | 説明 |
|---|---|---|
| `required_version` | 任意 | 実行を許可する Terraform CLI のバージョン制約（`infra/`・`infra/backend/` は `>= 1.10`（`infra/` は `use_lockfile` のため）、`infra/bootstrap/` は `>= 1.0`。使用中の CLI は 1.16.3）。 |
| `required_providers` | 任意 | 使用するプロバイダプラグインとバージョン制約の宣言（下記2参照）。 |
| `provider_meta` | 任意 | プロバイダが要求するモジュール単位のメタデータフィールド。 |
| `backend` | 任意（`cloud` と排他） | state の保存先。未指定時は既定でローカルファイル（`local`）。本プロジェクトの `infra/` は `backend "s3"` を使用（下記「`backend "s3"` ブロック内部」参照）。 |
| `cloud` | 任意（`backend` と排他） | HCP Terraform / Terraform Enterprise への接続設定。 |
| `experiments` | 任意 | 実験的言語機能フラグのリスト。 |

> `backend` と `cloud` は同一設定内で**併用不可**（相互排他）。本プロジェクトの `infra/` は `backend "s3"`（バケット `ts-030-bkt-tfstate`、キー `infra/terraform.tfstate`）で state を S3 に置きます。`infra/bootstrap/` と `infra/backend/` は `backend` 未指定のローカル state です（`.gitignore` 対象、[CLAUDE.md](../CLAUDE.md) 参照）。

## 1-1. `backend "s3"` ブロック内部（本プロジェクトで使用しているキー）

> state の置き場所・ロック・権限・復旧手順の全体像は [Terraform_stateの仕組み.md](Terraform_stateの仕組み.md) を参照してください。

| キー | 本プロジェクトの値 | 説明 |
|---|---|---|
| `bucket` | `ts-030-bkt-tfstate` | state を置く S3 バケット（別ルートモジュール `infra/backend/` で作成）。 |
| `key` | `infra/terraform.tfstate` | バケット内の state オブジェクトのキー。 |
| `region` | `ap-northeast-1` | バケットのリージョン。 |
| `profile` | `ts-030-usr-build` | 認証に使う名前付きプロファイル。 |
| `assume_role` | `{ role_arn = "arn:aws:iam::<アカウントID>:role/ts-030-role-build" }` | 引き受けるロール。provider の `assume_role` は**ブロック**だが、backend では**オブジェクト属性**（`= { ... }`）で書きます。 |
| `encrypt` | `true` | state オブジェクトをサーバー側で暗号化します。 |
| `use_lockfile` | `true` | S3 上に `<key>.tflock` オブジェクトを作成して排他します（Terraform 1.10+）。DynamoDB テーブルは不要。 |

## 2. `required_providers` 内部（プロバイダごとに指定）

| キー | 必須/任意 | 説明 |
|---|---|---|
| `source` | 任意（実質必須） | プロバイダのソースアドレス（`namespace/type` 形式。例 `hashicorp/aws`）。省略時は `hashicorp/<ローカル名>` とみなされます。 |
| `version` | 任意 | バージョン制約（`>=`/`~>` 等の演算子）。省略時は取得可能な最新版が使われます。 |

> 本プロジェクトの制約と `.terraform.lock.hcl` 上の実バージョン：aws `~> 5.0` → `5.100.0`、http `~> 3.0` → `3.6.0`、archive `~> 2.0` → `2.8.0`（`infra/backend/`・`infra/bootstrap/` は aws のみ、`~> 5.0` → `5.100.0`）。

## 3. `provider` ブロック（Terraform Core 共通キー）

| キー | 必須/任意 | 説明 |
|---|---|---|
| `alias` | 任意 | 同一プロバイダに対する複数設定を区別する識別子。`resource`/`module` 側で `provider = aws.west` のように参照します。 |
| `version`（非推奨） | 任意 | 旧来のバージョン制約指定方法。現在は `terraform.required_providers`側での指定が推奨。 |
| （プロバイダ固有引数） | — | `region` 等、各プロバイダが個別に定義する引数（下記4参照）。 |

> `alias` のないブロックがそのプロバイダの既定設定になります。子モジュールへは親の `provider` 設定が暗黙的に継承されます。

## 4. `provider "aws"` 固有の主な引数

| 分類 | 引数 | 説明 |
|---|---|---|
| 基本認証 | `region` | リージョン（本プロジェクトは `var.aws_region`）。 |
| 基本認証 | `access_key` / `secret_key` / `token` | 静的アクセスキー／シークレットキー／セッショントークン（本プロジェクトは未使用、`profile` を使用）。 |
| プロファイル | `profile` | 名前付きプロファイル（本プロジェクトは `var.assume_profile = "ts-030-usr-build"`）。 |
| プロファイル | `shared_config_files` / `shared_credentials_files` | `~/.aws/config` / `~/.aws/credentials` のパス上書き。 |
| ロール引受 | `assume_role`（ブロック） | IAM ロールを引き受けて実行する設定（下記5参照。本プロジェクトで使用）。 |
| ロール引受 | `assume_role_with_web_identity`（ブロック） | OIDC/OAuth（GitHub Actions OIDC 等）でのロール引受。 |
| タグ | `default_tags`（ブロック） | 全リソースへ自動付与する共通タグ（下記6参照。本プロジェクトで使用）。 |
| タグ | `ignore_tags`（ブロック） | Terraform の差分検出から除外するタグキー（下記7参照）。 |
| アカウント制御 | `allowed_account_ids` / `forbidden_account_ids` | 許可／禁止する AWS アカウント ID のリスト（誤った環境への apply 防止）。 |
| エンドポイント | `endpoints`（ブロック） / `sts_region` | サービスごとのカスタムエンドポイント／STS 専用リージョン。 |
| リトライ・性能 | `max_retries`（既定25） / `retry_mode`（`standard`/`adaptive`） | API リトライ制御。 |
| 検証スキップ | `skip_credentials_validation` / `skip_metadata_api_check` / `skip_region_validation` / `skip_requesting_account_id` | 各種事前検証の省略（オフライン開発・特殊環境向け）。 |
| ネットワーク | `http_proxy` / `https_proxy` / `no_proxy` / `custom_ca_bundle` / `insecure`（既定 `false`） | プロキシ・CA バンドル・SSL 検証省略。 |
| その他 | `use_fips_endpoint` / `use_dualstack_endpoint` | FIPS／デュアルスタックエンドポイントの使用。 |

## 5. `assume_role` ブロック内部

| キー | 必須/任意 | 説明 |
|---|---|---|
| `role_arn` | **必須** | 引き受ける IAM ロールの ARN（本プロジェクトは `ts-030-role-build`）。 |
| `session_name` | 任意 | AssumeRole セッション名。 |
| `external_id` | 任意 | 第三者へのロール貸与時に使う外部 ID。 |
| `policy` | 任意 | 引き受けたロールの権限をさらに絞り込む IAM ポリシー（JSON）。 |
| `policy_arns` | 任意 | 同上をマネージドポリシー ARN の集合で指定。 |
| `duration` | 任意 | セッション有効期間（`1h`/`2h45m`/`30m15s` 等の書式）。 |
| `tags` | 任意 | AssumeRole セッションタグのマップ。 |
| `transitive_tag_keys` | 任意 | 後続の AssumeRole チェーンへ引き継ぐタグキーの集合。 |
| `source_identity` | 任意 | ロール引受元プリンシパルが指定するソース ID。 |

> 本プロジェクトの `assume_role { role_arn = "..." }` は `role_arn` のみを指定する最小構成です。

## 6. `default_tags` ブロック内部

| キー | 必須/任意 | 説明 |
|---|---|---|
| `tags` | 任意 | このプロバイダで作成する全リソースへ自動付与するタグのマップ（本プロジェクトは `Project = var.project_tag`）。 |

## 7. `ignore_tags` ブロック内部

| キー | 必須/任意 | 説明 |
|---|---|---|
| `keys` | 任意 | Terraform の管理・差分検出から除外する完全一致タグキーのリスト。 |
| `key_prefixes` | 任意 | 除外するタグキーのプレフィックスのリスト。 |

## 8. 重要な注意点

- **`backend`/`cloud` は相互排他**: 本プロジェクトは `infra/` の state を `backend "s3"` で S3 に移行済みです（改善対象 B-5 / BUG-003 の再発防止）。バケットは別ルートモジュール `infra/backend/` で作成します。
- **`backend` ブロックでは変数・ローカル値・data を参照できない**: 値は直書きします。そのため `var.aws_account_id` 等は使えず、ロール ARN もリテラルで書きます（`infra/provider.tf` のコメント参照）。
- **backend を追加・変更したら `terraform init -migrate-state` が必要**: 本プロジェクトは `terraform init -migrate-state -force-copy` で既存のローカル state を S3 へ移しました（`run-terraform.log`（公開版には含めていません） 参照）。
- **backend の認証も構築ロール経由**: state へのアクセスにも `ts-030-role-build` が要るため、bootstrap を破棄している間は `infra` の `terraform init`/`plan` も実行できません。
- **`assume_role` は「借りる権限」を絞り込む仕組み**: `role_arn` が指すロールの Trust Policy（誰が引き受けられるか）とセットで機能します。詳細は [AssumeRoleまとめ.md](AssumeRoleまとめ.md) を参照。
- **`default_tags` と個別リソースの `tags` は同キーなら個別側が優先**: 本プロジェクトは `Project` タグを `default_tags` で一括付与し、個別リソースには書かない方針です（[CLAUDE.md](../CLAUDE.md) 参照）。なお `default_tags` は Terraform 管理外のリソースには効かないため、起動 Lambda が boto3 で作る EC2/EBS には `lambda_function.py` 側で `Project` タグを明示しています。
- **bootstrap は `assume_role` を使わない**: `infra/bootstrap/provider.tf` は `profile = var.role_admin_profile`（`ts-030-usr-role-admin`）で直接実行します。`infra/backend/provider.tf` は `infra/` と同じ AssumeRole 構成です。

## 9. 設定例（参考）

本プロジェクトの `infra/provider.tf` の構成です（アカウント ID は伏せ字）。

```hcl
terraform {
  required_version = ">= 1.10" # backend "s3" の use_lockfile が 1.10 以上を要求

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    http = {
      source  = "hashicorp/http"
      version = "~> 3.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.0"
    }
  }

  backend "s3" {
    bucket       = "ts-030-bkt-tfstate"
    key          = "infra/terraform.tfstate"
    region       = "ap-northeast-1"
    profile      = "ts-030-usr-build"
    assume_role  = { role_arn = "arn:aws:iam::<アカウントID>:role/ts-030-role-build" }
    encrypt      = true
    use_lockfile = true
  }
}

provider "aws" {
  region  = var.aws_region
  profile = var.assume_profile

  assume_role {
    role_arn = "arn:aws:iam::${var.aws_account_id}:role/${var.build_role_name}"
  }

  default_tags {
    tags = {
      Project = var.project_tag
    }
  }
}
```
