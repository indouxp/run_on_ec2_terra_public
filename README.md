# run_on_ec2_terra

S3 へのファイルアップロードを契機に EC2 を起動し、利用者のシェルスクリプト（run.sh）をバッチ実行する基盤です。インフラは Terraform で構築しています。

---

## システム概要（run_on_ec2_terra。プレフィックス ts-030）

<!-- Last updated: 2026-09-22 18:02:41（新規設計のシステムとして書き直し：設計方針を記載し、目的・実施フェーズを更新） -->

### システム概要

AWS S3 へのファイルアップロードを契機に、Lambda 関数が EC2 インスタンスを動的に起動し、バッチ処理（シェルスクリプト）を自動実行するイベント駆動型システムです。
処理完了後はアウトプット（結果）を S3 に保存し、SES（メール）と SMS で完了を通知してから、EC2 インスタンスが**自分自身を削除（terminate）**します。

### 設計方針

主な設計判断は次のとおりです（詳細は [docs/終了処理の簡素化.md](docs/終了処理の簡素化.md)、[docs/改善対象.md](docs/改善対象.md)）。

- **自己 terminate による1段の終了処理**：起動時に `InstanceInitiatedShutdownBehavior=terminate` を指定し、ジョブ完了後の `shutdown -h now` でインスタンスを削除します。停止を EventBridge で検知して終了 Lambda が削除する3段構成（案A）は、構成要素と権限が増えるため採用しませんでした。
- **SNS トピックを使わない通知**：SMS は電話番号へ直接 publish し、メールは SES で直接送信します。購読者を管理する必要が無いため、トピックは作りません。
- **Terraform で構築し、state は S3 に置く**：インフラは `infra/`・`infra/bootstrap/`・`infra/backend/` の3つのルートモジュールで構築し、`infra/` の state は S3（`ts-030-bkt-tfstate`）に置きます。
- **最小権限の運用**：管理者を常用せず、構築・データ運用・参照を用途別のユーザーと AssumeRole で分けます。

### 処理の流れ

```
ユーザー（work/ で ../tool/upl-run.sh を実行）
  ↓ S3 入力バケットに 入力ファイル → run.sh → run.conf の順にアップロード
S3 (ts-030-bkt-in)
  ↓ S3 イベント通知（.conf ファイルの作成を検知）
Lambda 起動関数 (ts-030-lmd-010)
  ↓ 定義ファイルを検証 → EC2 を起動（Project / autogen-by タグ付き）
EC2 インスタンス (ts-030-ec2-010。user_data で自律実行)
  ├─ CloudWatch Agent 起動（ログは ts-030-log-ec2-010 へ）
  ├─ S3 から実行ファイル・入力ファイルをダウンロード
  ├─ シェルスクリプト（run.sh）を実行（run.conf の timeout で打ち切り）
  ├─ 結果ファイルを S3 出力バケット (ts-030-bkt-out) へアップロード
  ├─ メール (SES) / SMS (電話番号へ直接) で完了通知
  └─ shutdown -h now → EC2 が自分自身を terminate（EBS も削除）
ユーザー
  ↓ ../tool/pop-s3.sh で結果を取得、../tool/del-s3.sh で入力を削除
```

### AWS アーキテクチャ

| コンポーネント | リソース名 | 役割 |
|---|---|---|
| S3 入力バケット | `ts-030-bkt-in` | run.conf / run.sh / 入力ファイルの受け取り |
| S3 出力バケット | `ts-030-bkt-out` | 結果ファイル・ログの保存 |
| Lambda 起動関数 | `ts-030-lmd-010` | 定義ファイル検証・EC2 起動 |
| EC2 インスタンス | `ts-030-ec2-010` | バッチ処理の自律実行環境（処理後に自己 terminate） |
| IAM ロール (Lambda) | `ts-030-role-lambda-010` | Lambda の権限制御 |
| IAM ロール (EC2) | `ts-030-role-ec2-010`（同名の Instance Profile） | EC2 の権限制御 |
| IAM ロール (データ運用) | `ts-030-role-operate` | in/out のデータ操作（tool/*.sh） |
| IAM ロール (構築) | `ts-030-role-build` | Terraform の実行（`infra/bootstrap/` で作成） |
| セキュリティグループ | `ts-030-sg-010` | SSH は実行元グローバル IP /32 のみ、アウトバウンドは全許可 |
| VPC / サブネット | `ts-030-vpc-010` / `ts-030-subnet-010` | ネットワーク基盤（IGW `ts-030-igw-010`、ルートテーブル `ts-030-rtt-010`） |
| SES | —（email identity は手動登録） | メール通知 |
| SMS | —（SNS トピックは作らず電話番号へ直接 publish） | SMS 通知 |
| CloudWatch Logs | `ts-030-log-ec2-010`、`/aws/lambda/ts-030-lmd-010` | EC2 と Lambda のログ（`ts-030-log-lambda-010`・`ts-030-log-system-010` も作成済みだが未使用。改善対象 B-6） |
| CloudTrail | `ts-030-trail-010`（ログは `ts-030-bkt-cloudtrail-logs`） | API 監査ログ |
| Terraform state | `ts-030-bkt-tfstate` | `infra/` の state（`infra/backend/` で作成・常設） |

### 定義ファイル（run.conf）の主要パラメータ

```json
{
  "prj_prefix": "ts-030",
  "exec": "run.sh input.tar.gz",
  "log": "run.log",
  "result": "*.mp4 *act.log",
  "mail": "user@example.com",
  "sms": "+819012345678",
  "instance_type": "c6i.4xlarge",
  "ebs_size": 50,
  "timeout": 21600,
  "output_bucket": "ts-030-bkt-out",
  "ses_from_email": "sender@example.com",
  "ec2_role_name": "ts-030-role-ec2-010",
  "subnet_name": "ts-030-subnet-010",
  "sg_name": "ts-030-sg-010",
  "ec2_instance_name_tag": "ts-030-ec2-010"
}
```

- 必須キーは `exec`・`log`・`result`・`mail`・`sms`・`ec2_role_name`・`subnet_name`・`sg_name`・`ec2_instance_name_tag`・`output_bucket`・`ses_from_email`・`prj_prefix` の12個です。`instance_type`・`ebs_size`・`timeout`（秒、未指定時 21600）などは任意です。
- メールアドレス・電話番号を含むため、実際の run.conf は `work/`（`.gitignore` 済み）に置きます。

### 費用概算（8回/月実行想定）

| サービス | 月額概算 |
|---|---|
| Lambda | $0.01 |
| EC2 (c6i.4xlarge × 13分 × 8回) | $1.50 |
| S3 (10GB) | $1.00 |
| SMS（SNS の直接 publish、8通） | $0.05 |
| SES (メール 8通) | $0.01 |
| **合計** | **約 $2.60/月** |

---

## このプロジェクト（run_on_ec2_terra）の目的

1. **バッチ実行基盤の提供**: S3 に入力と run.sh を置くだけで、必要なときだけ EC2 を起動して処理し、結果を受け取れるようにします。
2. **Terraform による再現可能な構築**: インフラをコードで管理し、全削除→再構築を繰り返せる状態に保ちます。
3. **ポートフォリオ**: 本リポジトリ（S3 経由で run.sh を実行する仕組みを Terraform で構築したもの）そのものをポートフォリオとします。

---

## このプロジェクトでの構成と実行手順

<!-- Last updated: 2026-09-22 18:02:41（設計方針の記述を「システム概要」に集約） -->

処理の流れと、`work/` から実行する運用スクリプトの対応は次のとおりです。

```
ユーザー（work/ で実行）
  ↓ ../tool/upl-run.sh run.conf   入力 → 実行シェル → run.conf の順に S3 in へ（run.conf の検査・起動前の確認あり）
S3 (ts-030-bkt-in)
  ↓ .conf の作成を検知
Lambda (ts-030-lmd-010)           run.conf を検証し EC2 を起動（Project / autogen-by タグ付き）
  ↓
EC2 (ts-030-ec2-010, user_data)   入力を取得 → run.sh（timeout 付き）→ 結果を S3 out へ → SMS・メール → 自己 terminate
  ↓
../tool/get-now.sh                状態の確認（EC2・S3・Lambda と EC2 のログ末尾）
../tool/pop-s3.sh                 out の結果を取得し、取得できた分を削除
../tool/del-s3.sh                 in を削除
```

- データ操作は `~/.aws/config` のプロファイル `ts-030-role-operate`（`ts-030-usr-operate` が AssumeRole）で行い、管理者権限は使いません。詳細は [docs/運用ユーザーと再作成手順.md](docs/運用ユーザーと再作成手順.md) の第8章を参照してください。
- 2026-09-22 に E2E（投入 → EC2 起動 → 変換 → 結果の出力 → SMS・メール着信 → 自己 terminate）が成功しています。
- 文書の一覧は [docs/文書一覧.md](docs/文書一覧.md) です。

## 実施フェーズ

詳細な作業リストは [docs/WBS.md](docs/WBS.md) を参照してください。

### フェーズ2：S3 起動バッチ実行基盤の構築（Terraform）

2026-09-22 に完了しました。次の順に構築しました。

1. VPC・サブネット・セキュリティグループ
2. S3 バケット・IAM ロール
3. Lambda 関数（終了処理は自己 terminate のため、終了用の Lambda・EventBridge は作りません）
4. CloudWatch Logs・CloudTrail（SES の email identity は手動で登録します）
5. 統合テスト（E2E）

### フェーズ3

このシステムでは実施しません（2026-09-22 決定）。本リポジトリ（S3 経由で run.sh を実行する仕組みを Terraform で構築したもの）をポートフォリオとします。

---

## 文書の理解順序

<!-- Last updated: 2026-09-23 01:12:41（Terraform_stateの仕組み.md を理解順序に追加） -->

このシステムを理解するときは、次の順に読むことを勧めます。全体像 → 仕組み（処理の流れ・権限）→ 運用 → Terraform の詳細 → 経緯、の順です。わからない用語は、そのつど [用語一覧](docs/用語一覧.md) を引いてください。

### 1. 全体像をつかむ

| 順 | 文書 | 読む目的 |
|:-:|------|----------|
| 1 | [README.md](README.md)（本書） | システム概要・設計方針・処理の流れ、構成と実行手順 |
| 2 | [docs/文書一覧.md](docs/文書一覧.md) | 文書と Terraform コードの全体地図（どこに何があるか） |
| 3 | [docs/用語一覧.md](docs/用語一覧.md) | 用語集。以降の文書を読みながら参照します |
| 4 | [docs/WBS.md](docs/WBS.md) | 何を・いつ・どの順で作ったか（完了日と確認根拠） |

### 2. 仕組みを理解する

| 順 | 文書 | 読む目的 |
|:-:|------|----------|
| 5 | [docs/終了処理の簡素化.md](docs/終了処理の簡素化.md) | EC2 が処理後に自分で terminate する仕組み（検討した案と採用理由） |
| 6 | [docs/ユーザーとロール一覧.md](docs/ユーザーとロール一覧.md) | IAM ユーザー・ロールの全体と、S3 のアクセス制御（許可と Deny フェンス） |
| 7 | [docs/AssumeRoleまとめ.md](docs/AssumeRoleまとめ.md) | 権限を「借りる」AssumeRole の仕組み（Terraform と CLI での書き方） |
| 8 | [docs/IAM最小権限の仕組み.md](docs/IAM最小権限の仕組み.md) | 構築ロールの設計、bootstrap が必要な理由、現状の限界と改善案 |
| 9 | [docs/Terraform_stateの仕組み.md](docs/Terraform_stateの仕組み.md) | Terraform state の置き場所（S3 とローカル）、state 用バケットの設計、ロック、権限、旧版への復旧手順 |
| 10 | [docs/ARN_ID_summary.md](docs/ARN_ID_summary.md) | ID と ARN の違い（IAM ポリシーを読むための補足） |

### 3. 運用を理解する

| 順 | 文書 | 読む目的 |
|:-:|------|----------|
| 11 | [docs/運用ユーザーと再作成手順.md](docs/運用ユーザーと再作成手順.md) | プロファイルの準備、state の置き場所、破棄・再作成、データ運用（tool/*.sh）、トラブル対応 |
| 12 | [docs/operation.md](docs/operation.md) | 実際の操作とその出力（tar.gz 作成 → 投入 → 状態確認 → 結果取得 → 削除） |
| 13 | [docs/ts-030-usr-buildユーザーの作成.md](docs/ts-030-usr-buildユーザーの作成.md) | コンソールで運用ユーザーを作る画面例（必要なときだけ） |

### 4. Terraform の詳細を理解する

コード（`infra/*.tf`）と引数リファレンスを並べて読みます。各 `.tf` の分担は [CLAUDE.md](CLAUDE.md) の「infra/*.tf の分担」にあります。

| 順 | 文書 | 対応するコード |
|:-:|------|----------------|
| 14 | [docs/provider_parameter.md](docs/provider_parameter.md) | `infra/provider.tf`（AssumeRole・default_tags・S3 バックエンド） |
| 15 | [docs/variable_parameter.md](docs/variable_parameter.md)・[docs/output_parameter.md](docs/output_parameter.md) | `infra/variables.tf`・`terraform.tfvars`・`outputs.tf` |
| 16 | [docs/VPC_parameter.md](docs/VPC_parameter.md)・[docs/subnet_parameter.md](docs/subnet_parameter.md)・[docs/internet_gateway_parameter.md](docs/internet_gateway_parameter.md)・[docs/route_table_parameter.md](docs/route_table_parameter.md) | `infra/network.tf` |
| 17 | [docs/security_group_parameter.md](docs/security_group_parameter.md) | `infra/security.tf` |
| 18 | [docs/S3_parameter.md](docs/S3_parameter.md) | `infra/storage.tf`・`monitoring.tf`（ログ用バケット）・`backend/state_bucket.tf` |
| 19 | [docs/IAM_parameter.md](docs/IAM_parameter.md) | `infra/iam.tf`・`bootstrap/iam_build_role.tf` |
| 20 | [docs/lambda_parameter.md](docs/lambda_parameter.md) | `infra/compute.tf`（Lambda 本体は `infra/lambda/lambda_function.py`・`user_data_template.sh`） |
| 21 | [docs/monitoring_parameter.md](docs/monitoring_parameter.md) | `infra/monitoring.tf` |

### 5. 経緯と今後を知る

| 順 | 文書 | 読む目的 |
|:-:|------|----------|
| 22 | [docs/不具合一覧.md](docs/不具合一覧.md) | 実際に起きた不具合・原因・再発防止（BUG-001〜007） |
| 23 | [docs/改善対象.md](docs/改善対象.md) | 対応済み・未対応の改善項目と判断の理由 |
| 24 | [docs/run-terraform.log](docs/run-terraform.log) ほか `docs/*.log` | 端末移行・state 復旧・再構築のときの実行記録（必要なときに参照） |
