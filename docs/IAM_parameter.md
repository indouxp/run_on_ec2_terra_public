# IAM ロール関連リソース 設定可能キー（Argument Reference）
<!-- Last updated: 2026-09-22 18:03:31（設定例の説明を本システムの構成に合わせ、Statement 数を実コードに合わせ、文体を統一） -->

Terraform AWS Provider（本プロジェクトの固定バージョン `~> 5.0`、`.terraform.lock.hcl` 上の実バージョン `5.100.0`）の公式ドキュメントに基づく、IAM ロール関連リソースで設定可能なキー（引数）の一覧です。

本プロジェクトでは、以下4リソースを組み合わせて IAM ロールを構成します（`infra/iam.tf`：Lambda／EC2 実行ロールとデータ運用ロール `ts-030-role-operate`。構築ロール `ts-030-role-build` は `infra/bootstrap/iam_build_role.tf` で同じく `aws_iam_role`＋`aws_iam_role_policy` を使用）。

- `aws_iam_role` … ロール本体（Trust Policy を持つ）
- `aws_iam_role_policy` … インラインの Permission Policy（1リソース = 1ポリシー文書）
- `aws_iam_role_policy_attachment` … AWS 管理ポリシーのアタッチ（1リソース = 1アタッチ）
- `aws_iam_instance_profile` … EC2 にロールを渡すための入れ物

> 注記: 本一覧は **AWS Provider 最新版**の Argument Reference に基づいています。`required_providers` で固定しているプロバイダーバージョンによって、引数の有無や挙動に差異が出る可能性があります。

---

## 0. なぜ個別リソースに分けるのか（設計方針）

`aws_iam_role` には、インラインポリシーを排他管理する `inline_policy` 引数と、マネージドポリシーのアタッチを排他管理する `managed_policy_arns` 引数が存在しますが、**いずれも非推奨（Deprecated）** です。これらを `aws_iam_role_policy` / `aws_iam_role_policy_attachment`（個別リソース）と同一ロールに対して併用すると、双方が同じ状態の管理を奪い合い、Terraform が恒久的な差分（drift）を表示し続けます。

本プロジェクトは `inline_policy` / `managed_policy_arns` を**使わず**、`aws_iam_role_policy`（インラインポリシー）と `aws_iam_role_policy_attachment`（マネージドポリシー）の個別リソースのみでロールの権限を管理します。

---

## 1. `aws_iam_role`（ロール本体）

### 1-1. トップレベルの引数

| キー | 必須/任意 | 説明 |
|---|---|---|
| `name` | 任意（変更で再作成） | ロール名。省略時はランダムな一意名。`name_prefix` と排他。 |
| `name_prefix` | 任意（変更で再作成） | 指定プレフィックスで始まる一意名を生成。`name` と排他。 |
| `path` | 任意 | ロールのパス。既定 `/`。 |
| `description` | 任意 | ロールの説明。 |
| `assume_role_policy` | **必須** | Trust Policy（誰がこのロールを AssumeRole できるか）。JSON 文字列。`jsonencode()` または `aws_iam_policy_document` データソースで記述します。 |
| `force_detach_policies` | 任意（既定 `false`） | ロール削除前に、アタッチ済みマネージドポリシーを強制デタッチするか。 |
| `max_session_duration` | 任意（既定 3600 秒） | AssumeRole セッションの最大継続時間（秒）。1時間〜12時間の範囲。 |
| `permissions_boundary` | 任意 | このロールに設定するパーミッションバウンダリのポリシー ARN。 |
| `inline_policy` | 任意・**非推奨** | インラインポリシーを排他管理するブロック（`name`/`policy`）。本プロジェクトは未使用（[0. 設計方針](#0-なぜ個別リソースに分けるのか設計方針)参照）。 |
| `managed_policy_arns` | 任意・**非推奨** | アタッチするマネージドポリシー ARN の集合を排他管理。本プロジェクトは未使用。 |
| `tags` | 任意 | ロールに付与するタグのマップ。`default_tags` と同キーは本リソース側が優先。 |

### 1-2. Attribute（参照のみ・設定不可）

| Attribute | 説明 |
|---|---|
| `id` | ロール名（`name` と同値）。 |
| `arn` | ロールの ARN。他リソースの Trust Policy 等から参照します。 |
| `unique_id` | AWS が割り当てる安定した一意識別子。 |
| `create_date` | ロール作成日時。 |
| `tags_all` | `default_tags` を含む全タグのマップ。 |

---

## 2. `aws_iam_role_policy`（インラインポリシー）

| キー | 必須/任意 | 説明 |
|---|---|---|
| `name` | 任意 | インラインポリシー名。省略時はランダムな一意名。`name_prefix` と排他。 |
| `name_prefix` | 任意 | 指定プレフィックスで始まる一意名を生成。 |
| `role` | **必須** | ポリシーをアタッチする IAM ロール名（`aws_iam_role.xxx.id` または `.name`）。 |
| `policy` | **必須** | Permission Policy 本体（JSON 文字列）。`jsonencode()` 推奨。 |

### Attribute
このリソース固有の参照専用属性はありません（`id` 等の暗黙属性のみ）。

---

## 3. `aws_iam_role_policy_attachment`（マネージドポリシーのアタッチ）

| キー | 必須/任意 | 説明 |
|---|---|---|
| `role` | **必須** | ポリシーをアタッチする IAM ロール名。 |
| `policy_arn` | **必須** | アタッチする AWS 管理ポリシー（またはカスタマー管理ポリシー）の ARN。 |

### Attribute
このリソース固有の参照専用属性はありません。

> 1ロールに複数のポリシーをアタッチする場合は、本リソースをポリシーの数だけ定義します（1リソース = 1アタッチ）。

---

## 4. `aws_iam_instance_profile`（EC2 用 Instance Profile）

| キー | 必須/任意 | 説明 |
|---|---|---|
| `name` | 任意（変更で再作成） | Instance Profile 名。**AWS アカウント内でグローバルに一意**（`path`/`role` が異なっても重複不可、重複時は `EntityAlreadyExists`）。省略時はランダムな一意名。 |
| `name_prefix` | 任意（変更で再作成） | 指定プレフィックスで始まる一意名を生成。`name` と排他。 |
| `path` | 任意（既定 `/`） | Instance Profile のパス。 |
| `role` | 任意 | 追加する IAM ロール名。**1 Instance Profile につき 1 ロールのみ**（AWS 側の制約）。 |
| `tags` | 任意 | タグのマップ。 |

### Attribute（参照のみ・設定不可）

| Attribute | 説明 |
|---|---|
| `id` | Instance Profile の ID。 |
| `arn` | Instance Profile の ARN。EC2 の `iam_instance_profile` 等から参照。 |
| `unique_id` | AWS が割り当てる一意 ID（GUID）。 |
| `create_date` | 作成日時。 |
| `tags_all` | `default_tags` を含む全タグ。 |

---

## 5. 重要な注意点

- **`inline_policy`/`managed_policy_arns` と個別リソースの併用不可**: `aws_iam_role` 側の非推奨引数と `aws_iam_role_policy`/`aws_iam_role_policy_attachment` を同一ロールに使うと、Terraform が恒久的な差分を出し続けます。本プロジェクトは個別リソースのみを使用しています。
- **`aws_iam_instance_profile.name` はアカウント内で完全一意**: `role`/`path` が異なっていても既存の `name` と重複すると作成に失敗します。他の3リソースにはこの制約はありません。
- **ロール名変更時の `force_detach_policies`**: `aws_iam_policy_attachment`（本プロジェクトでは未使用の別リソース）経由でアタッチされたポリシーがある場合、`force_detach_policies=true` が事前適用されていないと削除時に `DeleteConflict` が発生します。`aws_iam_role_policy_attachment` のみを使う本プロジェクトの構成ではこの制約は生じません。
- **Trust Policy と Permission Policy は別物**: `assume_role_policy`（誰がなれるか）と `aws_iam_role_policy` の `policy`（何ができるか）は独立したポリシーです。詳細は [IAM最小権限の仕組み.md](IAM最小権限の仕組み.md) / [用語一覧.md](用語一覧.md) を参照。

---

## 6. 設定例（参考）

本プロジェクトの `infra/iam.tf` から、Lambda 実行ロール一式と EC2 用 Instance Profile を抜粋しています。インラインポリシーは Statement の一部のみ示します（実際は in の GetObject・EC2 起動系・タグ条件付き TerminateInstances・PassRole・SNS・SES の6文です）。コード中のコメントは説明用に書き換えています。

```hcl
# 説明用: ロール本体（Trust Policy: lambda.amazonaws.com が AssumeRole）
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

# 説明用: AWS 管理ポリシーのアタッチ（CloudWatch Logs 出力用）
resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# 説明用: インラインポリシー（固有の Permission Policy）
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
      }
    ]
  })
}

# 説明用: EC2 用 Instance Profile（名前はロールと同名。Lambda が同名で引いて EC2 に付与する）
resource "aws_iam_instance_profile" "ec2" {
  name = "${var.prj_prefix}-role-ec2-010"
  role = aws_iam_role.ec2.name

  tags = {
    Name = "${var.prj_prefix}-role-ec2-010"
  }
}
```
