# S3 バケット関連リソース 設定可能キー（Argument Reference）
<!-- Last updated: 2026-09-23 01:12:41（state の仕組みの文書へのリンクを追加） -->

Terraform AWS Provider（本プロジェクトの固定バージョン `~> 5.0`、`.terraform.lock.hcl` 上の実バージョン `5.100.0`）の公式ドキュメントに基づく、S3 バケット関連リソースで設定可能なキー（引数）の一覧です。

本プロジェクトでは、以下のリソースを組み合わせて S3 バケットを構成します。バケットは4つです。

| バケット | 用途 | 定義場所 |
|---|---|---|
| `ts-030-bkt-in` / `ts-030-bkt-out` | 入力・出力データ | `infra/storage.tf` |
| `ts-030-bkt-cloudtrail-logs` | CloudTrail ログ | `infra/monitoring.tf` |
| `ts-030-bkt-tfstate` | `infra/` の Terraform state | `infra/backend/state_bucket.tf` |

> state 用バケットの役割と、state の運用・復旧手順は [Terraform_stateの仕組み.md](Terraform_stateの仕組み.md) を参照してください。


- `aws_s3_bucket` … バケット本体
- `aws_s3_bucket_public_access_block` … パブリックアクセスブロック
- `aws_s3_bucket_server_side_encryption_configuration` … 既定の暗号化
- `aws_s3_bucket_ownership_controls` … 所有者制御（ACL 無効化）
- `aws_s3_bucket_versioning` … バージョニング（state 用バケットのみ）
- `aws_s3_bucket_lifecycle_configuration` … ライフサイクル（自動削除）
- `aws_s3_bucket_policy` … バケットポリシー（in/out は Deny フェンス、CloudTrail 用は配信許可、state 用は TLS 以外の拒否）
- `aws_s3_bucket_notification` … イベント通知（Lambda トリガー。in のみ）

> 注記: 本一覧は **AWS Provider 最新版**の Argument Reference に基づいています。`required_providers` で固定しているプロバイダーバージョンによって、引数の有無や挙動に差異が出る可能性があります。調査時点で開発版（次期リリース）にのみ存在が確認され、本プロジェクトの固定バージョンでの対応が未確認の項目（`region` 引数、`bucket_namespace`、`blocked_encryption_types` 等）は本一覧には含めていません。

---

## 0. なぜ本体と設定を分けるのか（設計方針）

`aws_s3_bucket` には、かつて ACL・CORS・ライフサイクル・ロギング・バージョニング・Website・バケットポリシー・暗号化設定などを直接書けるインライン引数がありましたが、Provider v4→v5 でこれらはすべて**個別リソースへ分離**されました（旧引数は非推奨のまま残存するが、分離後リソースと同一バケットへの併用は不可）。

本プロジェクトはこの分離後の設計に沿い、`aws_s3_bucket` を「箱」だけの定義に留め、パブリックアクセスブロック・暗号化・所有者制御・バージョニング（state 用のみ）・ライフサイクル・ポリシー・通知をそれぞれ専用リソースで定義します。4バケットすべてに、パブリックアクセスブロック4項目・SSE-S3（AES256）＋バケットキー・BucketOwnerEnforced を設定しています（CloudTrail は既定 ACL `bucket-owner-full-control` で配信するが、BucketOwnerEnforced でも受け付けられる）。

---

## 1. `aws_s3_bucket`（バケット本体）

### 1-1. トップレベルの引数

| キー | 必須/任意 | 説明 |
|---|---|---|
| `bucket` | 任意（変更で再作成） | バケット名。**グローバルに一意**。省略時はランダムな一意名を自動生成。`bucket_prefix` と排他。 |
| `bucket_prefix` | 任意（変更で再作成） | 指定プレフィックスで一意名を自動生成。`bucket` と排他。 |
| `force_destroy` | 任意（既定 `false`） | `terraform destroy` 時にバケット内オブジェクトを全削除してからバケットを削除するか。本プロジェクトでは CloudTrail ログ用バケットのみ `true`（証跡が常時ログを書くため、無いと `BucketNotEmpty` で destroy が失敗します。**destroy で監査ログも消えます**）。in/out は未指定（`false`）。state 用バケットは中身ごと消えると復旧できないため意図して付けません。オブジェクト削除には実行主体に `s3:DeleteObject`（バージョニング無効時）／`s3:DeleteObjectVersion` が必要（BUG-004）。 |
| `object_lock_enabled` | 任意（変更で再作成） | Object Lock（改ざん防止）を有効化するか。 |
| `tags` | 任意 | タグのマップ。 |

### 1-2. 非推奨（Deprecated）だが残存する引数

以下は v4 以前のインライン設定で、現在は個別リソースへの分離が推奨されます。同一バケットに対して個別リソースと**併用できません**（drift の原因）。

| 旧引数 | 分離先の個別リソース |
|---|---|
| `acl` / `grant` | `aws_s3_bucket_acl` |
| `cors_rule` | `aws_s3_bucket_cors_configuration` |
| `lifecycle_rule` | `aws_s3_bucket_lifecycle_configuration`（本プロジェクトで使用） |
| `logging` | `aws_s3_bucket_logging` |
| `object_lock_configuration` | `aws_s3_bucket_object_lock_configuration` |
| `policy` | `aws_s3_bucket_policy`（本プロジェクトで使用） |
| `replication_configuration` | `aws_s3_bucket_replication_configuration` |
| `request_payer` | `aws_s3_bucket_request_payment_configuration` |
| `server_side_encryption_configuration` | `aws_s3_bucket_server_side_encryption_configuration`（本プロジェクトで使用） |
| `versioning` | `aws_s3_bucket_versioning`（本プロジェクトで使用：state 用バケット） |
| `website` | `aws_s3_bucket_website_configuration` |
| `acceleration_status` | `aws_s3_bucket_accelerate_configuration` |

### 1-3. Attribute（参照のみ・設定不可）

| Attribute | 説明 |
|---|---|
| `id` | バケット名（`bucket` と同値）。 |
| `arn` | バケットの ARN。バケットポリシー・IAM ポリシーの `Resource` から参照します。 |
| `bucket_domain_name` | `<bucket>.s3.amazonaws.com` 形式のドメイン名。 |
| `bucket_regional_domain_name` | リージョン固有のドメイン名。 |
| `bucket_region` | バケットが存在するリージョン。 |
| `hosted_zone_id` | Route 53 Hosted Zone ID。 |
| `tags_all` | `default_tags` を含む全タグ。 |

---

## 2. `aws_s3_bucket_public_access_block`

| キー | 必須/任意 | 説明 |
|---|---|---|
| `bucket` | **必須** | 対象バケット名。 |
| `block_public_acls` | 任意（既定 `false`） | パブリック ACL の設定をブロック。 |
| `ignore_public_acls` | 任意（既定 `false`） | 既存のパブリック ACL を無視。 |
| `block_public_policy` | 任意（既定 `false`） | パブリックなバケットポリシーの設定をブロック。 |
| `restrict_public_buckets` | 任意（既定 `false`） | パブリックポリシーを持つバケットへのアクセスを制限。 |
| `skip_destroy` | 任意 | `destroy` 時に AWS 側の設定を残し、state からのみ削除するか。 |

### Attribute
`id`（適用先バケット名）以外の固有属性なし。

---

## 3. `aws_s3_bucket_server_side_encryption_configuration`

| キー | 必須/任意 | 説明 |
|---|---|---|
| `bucket` | **必須**（変更で再作成） | 対象バケット名。 |
| `expected_bucket_owner`（非推奨） | 任意 | 想定するバケット所有者のアカウント ID。 |
| `rule`（ブロック） | **必須** | 暗号化ルール。 |
| `rule.apply_server_side_encryption_by_default.sse_algorithm` | **必須** | `AES256`（SSE-S3）または `aws:kms`（SSE-KMS）。 |
| `rule.apply_server_side_encryption_by_default.kms_master_key_id` | 任意 | `sse_algorithm = "aws:kms"` の場合の KMS キー ID。 |
| `rule.bucket_key_enabled` | 任意 | S3 Bucket Keys（KMS 呼び出しコスト削減）の有効化。 |

### Attribute
`id`（`bucket`）以外の固有属性なし。

> `destroy` すると暗号化設定は S3 の既定値にリセットされます（暗号化自体が無効になるわけではない）。

---

## 4. `aws_s3_bucket_ownership_controls`

| キー | 必須/任意 | 説明 |
|---|---|---|
| `bucket` | **必須** | 対象バケット名。 |
| `rule.object_ownership` | **必須** | `BucketOwnerPreferred` / `ObjectWriter` / `BucketOwnerEnforced`（ACL 無効化・所有者に完全制御を強制。本プロジェクトの設定値）のいずれか。 |

### Attribute
`id`（バケット名）以外の固有属性なし。

---

## 5. `aws_s3_bucket_lifecycle_configuration`

### 5-1. トップレベル

| キー | 必須/任意 | 説明 |
|---|---|---|
| `bucket` | **必須** | 対象バケット名。 |
| `rule`（ブロック・複数可） | **必須** | ライフサイクルルール。 |
| `expected_bucket_owner`（非推奨） | 任意（変更で再作成） | 想定バケット所有者のアカウント ID。 |

### 5-2. `rule` ブロック内

| キー | 必須/任意 | 説明 |
|---|---|---|
| `id` | **必須** | ルール識別子（255文字以内）。 |
| `status` | **必須** | `Enabled` / `Disabled`。 |
| `filter` | 任意 | 対象オブジェクトの絞り込み。`prefix`/`tag`/`and`/`object_size_greater_than`/`object_size_less_than` のいずれか、または**空 `filter {}`（バケット全体が対象。本プロジェクトの設定）**。 |
| `expiration` | 任意 | `date` または `days`（正の整数）で有効期限を指定。 |
| `transition`（複数可） | 任意 | `days`/`date` ＋ `storage_class`（`GLACIER`/`STANDARD_IA`等）でストレージクラス移行。 |
| `noncurrent_version_expiration` | 任意 | `noncurrent_days`（必須）で非最新バージョンの有効期限（本プロジェクトで使用：state 用バケットで `var.noncurrent_days` = 90 日。バージョニングが有効なバケットでのみ意味を持つ）。 |
| `noncurrent_version_transition`（複数可） | 任意 | 非最新バージョンのストレージクラス移行。 |
| `abort_incomplete_multipart_upload.days_after_initiation` | 任意 | 未完了マルチパートアップロードを N 日後に中断・削除。 |
| `prefix`（非推奨） | 任意 | `filter` への移行が推奨される旧引数。 |

### Attribute
`id`（`bucket`）以外の固有属性なし。

> **1バケットにつき本リソース1つのみ**定義します（複数定義は `PutBucketLifecycleConfiguration` が原子的置換のため永続的な差分の原因になる）。本プロジェクトは in/out で `filter {}`（空）を使い、バケット全体を `s3_expire_days`（既定・tfvars とも 30）日で `Expiration` します。state 用バケットは `filter {}` で `noncurrent_version_expiration`（旧バージョンのみ 90 日で削除、現行 state は消さない）を設定し、`depends_on = [aws_s3_bucket_versioning.tfstate]` でバージョニングの後に適用します。CloudTrail ログ用バケットにライフサイクルはありません。

---

## 6. `aws_s3_bucket_policy`

| キー | 必須/任意 | 説明 |
|---|---|---|
| `bucket` | **必須** | ポリシーを適用するバケット名。 |
| `policy` | **必須** | バケットポリシー本文（JSON 文字列、上限20KB）。`jsonencode()` または `aws_iam_policy_document`（`Principal` 指定必須）で記述。 |

### Attribute
固有属性なし。

> **1バケットにつき本リソース1つのみ**定義します（`PutBucketPolicy` は原子的置換のため、複数定義すると後から適用した方が黙って上書きする）。本プロジェクトでは in/out にそれぞれ1つずつ Deny フェンス（[用語一覧.md](用語一覧.md) 参照）を定義します。加えて、CloudTrail ログ用には CloudTrail サービスへの配信許可（`aws:SourceArn` 条件付き）、state 用には TLS 以外のアクセスを全面拒否する `aws:SecureTransport = false` の Deny を定義します（state 用は `depends_on` でパブリックアクセスブロックの後に適用）。

---

## 7. `aws_s3_bucket_notification`

### 7-1. トップレベル

| キー | 必須/任意 | 複数指定 | 説明 |
|---|---|---|---|
| `bucket` | **必須** | 不可 | 対象バケット名。 |
| `eventbridge` | 任意（既定 `false`） | 不可 | EventBridge への通知転送を有効化。 |
| `lambda_function`（ブロック） | 任意 | 可（本プロジェクトで使用） | Lambda 関数への通知。 |
| `queue`（ブロック） | 任意 | 可 | SQS キューへの通知。 |
| `topic`（ブロック） | 任意 | 可 | SNS トピックへの通知。 |

### 7-2. `lambda_function`/`queue`/`topic` 共通の内部キー

| キー | 必須/任意 | 説明 |
|---|---|---|
| `lambda_function_arn` / `queue_arn` / `topic_arn` | **必須** | 通知先の ARN。 |
| `events` | **必須** | 対象イベント（例: `s3:ObjectCreated:*`）。 |
| `filter_prefix` | 任意 | キー名プレフィックスによる絞り込み。 |
| `filter_suffix` | 任意 | キー名サフィックスによる絞り込み（本プロジェクトは `.conf` を使用）。 |
| `id` | 任意 | 通知設定の識別子。 |

### Attribute
固有属性なし。

> **1バケットにつき本リソース1つのみ**定義します（`PutBucketNotificationConfiguration` は原子的置換）。Lambda への通知には対応する `aws_lambda_permission`（S3 からの呼び出し許可）が事前に存在する必要があり、`depends_on` で明示します（本プロジェクトの設定どおり）。

---

## 8. `aws_s3_bucket_versioning`

| キー | 必須/任意 | 説明 |
|---|---|---|
| `bucket` | **必須** | 対象バケット名。 |
| `versioning_configuration`（ブロック） | **必須** | `status`（必須。`Enabled` / `Suspended` / `Disabled`）と `mfa_delete`（任意）。 |
| `mfa` | 任意 | MFA Delete を変更する場合の MFA デバイスのシリアルと値。 |
| `expected_bucket_owner`（非推奨） | 任意 | 想定バケット所有者のアカウント ID。 |

> 本プロジェクトでは state 用バケットのみ `status = "Enabled"`。state の旧世代を残し、誤った更新から戻せるようにします（旧世代の削除は構築ロールに対して明示 Deny）。

---

## 9. 重要な注意点

- **`aws_s3_bucket` の非推奨インライン引数と個別リソースの併用不可**: `policy`/`server_side_encryption_configuration`/`lifecycle_rule` 等を `aws_s3_bucket` に直接書くと、対応する個別リソースと競合します。
- **`aws_s3_bucket_lifecycle_configuration`/`_policy`/`_notification` はいずれも1バケット1リソース**: 複数定義は AWS API 側が原子的置換のため意図しない上書き・永続的差分の原因になります。
- **`filter {}`（空）は「絞り込みなし＝バケット全体」を意味する**: `aws_s3_bucket_lifecycle_configuration` の `rule.filter` に何も指定しない場合と同じ意味です。
- **`BucketOwnerEnforced` は ACL を完全に無効化する**: `aws_s3_bucket_public_access_block` と組み合わせて、ACL 経由の公開経路を根本的に断つ設計です（本プロジェクトの方針）。
- **`lifecycle { prevent_destroy = true }`**（Terraform のメタ引数で、S3 の引数ではない）: このリソースを破棄する plan をエラーにします。state 用バケットに設定し、Terraform からの誤削除を防ぎます。`force_destroy`（中身ごと消す）とは目的が逆です。

---

## 10. 設定例（参考）

本プロジェクトの `infra/storage.tf` の構成から、in/out 用を抜粋しています（見出しコメント・ポリシー・通知は省略）。in/out の2バケットを `for_each` で共通生成しています。

```hcl
resource "aws_s3_bucket" "this" {
  for_each = toset(["in", "out"])
  bucket   = "${var.prj_prefix}-bkt-${each.key}"

  tags = {
    Name = "${var.prj_prefix}-bkt-${each.key}"
  }
}

resource "aws_s3_bucket_public_access_block" "this" {
  for_each = aws_s3_bucket.this

  bucket                  = each.value.id
  block_public_acls       = true
  ignore_public_acls      = true
  block_public_policy     = true
  restrict_public_buckets = true
}

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

resource "aws_s3_bucket_ownership_controls" "this" {
  for_each = aws_s3_bucket.this

  bucket = each.value.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

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
```

state 用バケット（`infra/backend/state_bucket.tf`）の要点です（抜粋。タグ・パブリックアクセスブロック・暗号化・所有者制御・TLS 強制ポリシーは省略）。

```hcl
resource "aws_s3_bucket" "tfstate" {
  bucket = "${var.prj_prefix}-bkt-tfstate"

  lifecycle {
    prevent_destroy = true # Terraform からの誤削除を防ぐ（force_destroy は付けない）
  }
}

resource "aws_s3_bucket_versioning" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "tfstate" {
  bucket     = aws_s3_bucket.tfstate.id
  depends_on = [aws_s3_bucket_versioning.tfstate]

  rule {
    id     = "${aws_s3_bucket.tfstate.bucket}-noncurrent-${var.noncurrent_days}d"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      noncurrent_days = var.noncurrent_days # 90
    }
  }
}
```
