# 監視・証跡関連リソース 設定可能キー（Argument Reference）
<!-- Last updated: 2026-09-22 18:05:01（設計理由を本システムの判断として記述し、文体を統一） -->

Terraform AWS Provider（本プロジェクトの固定バージョン `~> 5.0`、`.terraform.lock.hcl` 上の実バージョン `5.100.0`）で設定可能なキー（引数）の一覧です。**引数の有無と必須／任意の区別は、使用中のプロバイダから `terraform providers schema -json` で取り出したスキーマに基づきます**（2026-09-22 取得）。

本プロジェクトでは、以下を組み合わせて監視・証跡を構成します（`infra/monitoring.tf`、WBS 2.8）。

- `aws_cloudwatch_log_group` … ロググループ（lambda / ec2 / system の3つ）。※ 実際に書き込まれているのは `ts-030-log-ec2-010`（EC2 の CloudWatch Agent）だけです。Lambda は `logging_config` 未指定のため既定の `/aws/lambda/ts-030-lmd-010` に出力し、system には書き込み元がありません（改善対象 B-6）
- `aws_cloudwatch_log_metric_filter` … メトリクスフィルタ（各ロググループの `"ERROR"` を計上）
- `aws_cloudtrail` … 証跡 `ts-030-trail-010`
- CloudTrail ログ用バケット `ts-030-bkt-cloudtrail-logs` とその PAB／暗号化／所有者制御／バケットポリシー … [S3_parameter.md](S3_parameter.md) を参照

> 本プロジェクトの決定事項：SNS トピックは作りません（SMS は電話番号へ直接 publish、Email は SES 直接送信のため未使用）。CloudWatch アラームは作りません。CloudWatch Logs の KMS 暗号化（改善対象 S-1）は不要と判断しています。

---

## 1. `aws_cloudwatch_log_group`

### 1-1. 引数

| キー | 必須/任意 | 説明 |
|---|---|---|
| `name` | 任意（変更で再作成） | ロググループ名。省略時は一意な名前を自動生成。`name_prefix` と排他。本プロジェクトは `${prj_prefix}-log-<lambda/ec2/system>-010`。 |
| `name_prefix` | 任意（変更で再作成） | 指定プレフィックスで一意名を自動生成。`name` と排他。 |
| `retention_in_days` | 任意 | ログの保持日数。`1`/`3`/`5`/`7`/`14`/`30`/`60`/`90`… など決められた値から選びます。未指定（`0`）は無期限保持。本プロジェクトは `30`。 |
| `kms_key_id` | 任意 | ログの暗号化に使う KMS キーの ARN。本プロジェクトは未指定（S-1 で不要と判断）。 |
| `log_group_class` | 任意 | ロググループのクラス（`STANDARD` / `INFREQUENT_ACCESS` 等）。未指定は `STANDARD`。 |
| `skip_destroy` | 任意 | `true` にすると destroy 時にロググループを削除せず、state から外すだけにします。本プロジェクトは未指定（destroy で削除）。 |
| `tags` | 任意 | タグのマップ。本プロジェクトは `Name` と `Component`（`Project` は `default_tags` で付与）。 |

### 1-2. Attribute（参照のみ）

| 属性 | 説明 |
|---|---|
| `arn` | ロググループの ARN。 |
| `id` | ロググループ名。 |
| `tags_all` | `default_tags` を含む全タグ。 |

---

## 2. `aws_cloudwatch_log_metric_filter`

### 2-1. トップレベル

| キー | 必須/任意 | 説明 |
|---|---|---|
| `name` | **必須** | メトリクスフィルタ名。本プロジェクトは `${prj_prefix}-<key>-error-filter`。 |
| `log_group_name` | **必須** | 対象のロググループ名。本プロジェクトは `aws_cloudwatch_log_group.this[each.key].name` を参照。 |
| `pattern` | **必須** | ログイベントに一致させるフィルタパターン。本プロジェクトは `"ERROR"`（その語を含むログ行）。 |
| `metric_transformation`（ブロック） | **必須（1つだけ）** | 一致したときに発行するメトリクスの定義（下記）。 |

### 2-2. `metric_transformation` ブロック

| キー | 必須/任意 | 説明 |
|---|---|---|
| `name` | **必須** | メトリクス名。本プロジェクトは `${prj_prefix}-<key>-errors`。 |
| `namespace` | **必須** | メトリクスの名前空間。本プロジェクトは `${prj_prefix}/<Lambda/EC2/System>`。 |
| `value` | **必須** | 一致1件ごとに発行する値。本プロジェクトは `"1"`（件数を数える）。 |
| `default_value` | 任意 | 一致しなかった期間に発行する値。 |
| `dimensions` | 任意 | メトリクスのディメンション（ログのフィールド名との対応）。 |
| `unit` | 任意 | メトリクスの単位。 |

> `id`（フィルタ名）以外の固有属性はありません。メトリクスフィルタは**タグを付けられない**ため、タグ検索（Resource Groups Tagging API）には出てきません（`tool/aws-describe-tagged-resources.sh` はロググループの describe の中で取得します）。

---

## 3. `aws_cloudtrail`

### 3-1. トップレベル

| キー | 必須/任意 | 説明 |
|---|---|---|
| `name` | **必須** | 証跡名。本プロジェクトは `${prj_prefix}-trail-010`。 |
| `s3_bucket_name` | **必須** | ログの配信先バケット名。本プロジェクトは `aws_s3_bucket.cloudtrail.id`（`ts-030-bkt-cloudtrail-logs`）。 |
| `s3_key_prefix` | 任意 | 配信先のキー接頭辞。本プロジェクトは未指定（`AWSLogs/<アカウントID>/CloudTrail/...` に配信）。 |
| `is_multi_region_trail` | 任意 | 全リージョンのイベントを記録するか。本プロジェクトは `true`。 |
| `include_global_service_events` | 任意 | IAM 等のグローバルサービスのイベントを含めるか。本プロジェクトは `true`。 |
| `enable_logging` | 任意 | ログ記録を有効にするか（`false` で停止）。本プロジェクトは `true`。 |
| `enable_log_file_validation` | 任意 | ログファイルの改ざん検知用ダイジェストを作るか。本プロジェクトは未指定（ダイジェストファイルは作りません）。 |
| `kms_key_id` | 任意 | ログの暗号化に使う KMS キーの ARN。本プロジェクトは未指定（SSE-S3 はバケット側で設定）。 |
| `cloud_watch_logs_group_arn` / `cloud_watch_logs_role_arn` | 任意 | CloudWatch Logs へも配信する場合のロググループ ARN と、配信に使う IAM ロール ARN（組で指定）。本プロジェクトは未使用。 |
| `sns_topic_name` | 任意 | ログ配信を通知する SNS トピック名。本プロジェクトは未使用（SNS トピックを作らない決定）。 |
| `is_organization_trail` | 任意 | AWS Organizations の組織全体の証跡にするか。本プロジェクトは未使用。 |
| `tags` | 任意 | タグのマップ。本プロジェクトは `Name`。 |

### 3-2. `event_selector` ブロック（最大5つ）

| キー | 必須/任意 | 説明 |
|---|---|---|
| `read_write_type` | 任意 | 記録するイベントの種類（`All` / `ReadOnly` / `WriteOnly`）。本プロジェクトは `All`。 |
| `include_management_events` | 任意 | 管理イベント（リソースの作成・変更等の API）を記録するか。本プロジェクトは `true`。 |
| `exclude_management_event_sources` | 任意 | 記録から除外する管理イベントのソース。 |
| `data_resource`（ブロック・複数可） | 任意 | データイベントの対象。`type`（必須）と `values`（必須）を指定（下記）。 |

`data_resource` ブロック：

| キー | 必須/任意 | 説明 |
|---|---|---|
| `type` | **必須** | 対象リソースの種類（例：`AWS::S3::Object`、`AWS::Lambda::Function`）。本プロジェクトは `AWS::S3::Object`。 |
| `values` | **必須** | 対象 ARN のリスト。本プロジェクトは `["arn:aws:s3:::"]`（**全バケット**のオブジェクト操作を記録）。 |

### 3-3. その他のブロック

| ブロック | 説明 |
|---|---|
| `advanced_event_selector`（複数可） | フィールド条件（`field_selector` の `field` と `equals` / `starts_with` / `ends_with` / `not_*`）でイベントを細かく選ぶ新方式。`event_selector` とは併用不可。本プロジェクトは未使用。 |
| `insight_selector`（複数可） | CloudTrail Insights（API 呼び出し量・エラー率の異常検知）の種類（`insight_type`）。本プロジェクトは未使用。 |

### 3-4. Attribute（参照のみ）

| 属性 | 説明 |
|---|---|
| `arn` | 証跡の ARN。 |
| `home_region` | 証跡を作成したリージョン。 |
| `sns_topic_arn` | 通知先 SNS トピックの ARN（`sns_topic_name` 指定時）。 |
| `id` / `tags_all` | 証跡名／`default_tags` を含む全タグ。 |

---

## 4. 重要な注意点

- **バケットポリシーを先に作る**: 配信先バケットに CloudTrail からの書き込みを許すポリシーが無いと、証跡の作成が失敗します。本プロジェクトは `depends_on = [aws_s3_bucket_policy.cloudtrail]` で順序を明示しています。ポリシーは混同代理（confused deputy）防止のため `aws:SourceArn` を当該証跡に限定し、ARN は依存の循環を避けるため文字列で組み立てます（`local.cloudtrail_arn`）。
- **データイベントは有料で量も多い**: `values = ["arn:aws:s3:::"]` はアカウント内の全バケットのオブジェクト操作を記録します。2026-07 から 9 月までで配信先バケットに約41,000オブジェクト溜まりました。
- **配信先バケットは `force_destroy = true`**: 証跡が常時ログを書くため、無いと destroy が `BucketNotEmpty` で失敗します。destroy で監査ログも消えます（[S3_parameter.md](S3_parameter.md)、[不具合一覧.md](不具合一覧.md) BUG-004）。
- **`event_selector` と `advanced_event_selector` は併用不可**: どちらか一方で書きます。
- **ロググループとメトリクスフィルタは `for_each` で3組**: `local.cw_targets`（lambda / ec2 / system）を共通の定義にして、名前・名前空間を組み立てています。
- **lambda・system のメトリクスフィルタは現状カウントされない**: 対象のロググループにログが来ないためです（改善対象 B-6）。
- **アラームは作らない**: メトリクスフィルタでエラー件数のメトリクスは発行されますが、それを監視する CloudWatch アラーム（と通知先 SNS）は作っていません。

---

## 5. 設定例（参考）

本プロジェクトの `infra/monitoring.tf` の構成です。CloudTrail ログ用バケットの定義は省略しています。`locals` 内のコメントは説明用に1行へまとめています。

```hcl
locals {
  # 説明用: key = リソースキー兼メトリクス種別、log_suffix = ロググループ名の中間語、namespace = 名前空間の末尾
  cw_targets = {
    lambda = { log_suffix = "lambda", namespace = "Lambda" }
    ec2    = { log_suffix = "ec2", namespace = "EC2" }
    system = { log_suffix = "system", namespace = "System" }
  }
}

resource "aws_cloudwatch_log_group" "this" {
  for_each = local.cw_targets

  name              = "${var.prj_prefix}-log-${each.value.log_suffix}-010"
  retention_in_days = 30

  tags = {
    Name      = "${var.prj_prefix}-log-${each.value.log_suffix}-010"
    Component = each.key
  }
}

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
```
