# run_on_ec2_terra

<!-- Last updated: 2026-10-29 08:49:58（公開版向けに「公開版について」「使用技術」「ディレクトリ構成」「セットアップの要点」「ライセンス」「免責事項」を追加） -->

S3 へのファイルアップロードを契機に EC2 を起動し、利用者のシェルスクリプト（run.sh）をバッチ実行する基盤です。インフラは Terraform で構築しています。

> **元プロジェクトとの関係**
> 本リポジトリは、公開済みの [run_on_ec2_public](https://github.com/indouxp/run_on_ec2_public)（S3 イベント連携による EC2 自動処理システム）を **Terraform 化**したものです。
> 元プロジェクトでシェルスクリプトと手作業で行っていた AWS リソースの構築を Terraform のコードに置き換え、あわせて終了処理の簡素化（EC2 の自己 terminate）、SNS トピックを使わない通知、最小権限の IAM 設計、S3 による state 管理などの見直しを行っています。

> **公開版について**
> 本リポジトリはポートフォリオとして公開するための版です。非公開の開発用リポジトリからコピーして作成しました。
> - AWS アカウント ID・メールアドレス・電話番号・リソース ID・端末名などは、例示用のダミー値（`123456789012`、`user@example.com`、`+819012345678`、`vpc-0123456789abcdef0` など）に置き換えています。スクリーンショットの個人情報は黒塗りしています。
> - Terraform の state、端末の実行ログ、AI とのセッション記録、作業ディレクトリ（`work/`）は含めていません。
> - 公開にあたって内容を調整しているため、実際に稼働させた実装とは一致しない場合があります。
> - 文書中のコミットハッシュ（例: `ed287e5`）は開発用リポジトリのもので、本リポジトリの履歴には存在しません。

## 使用技術

| 分類 | 技術 |
|---|---|
| IaC | Terraform 1.10 以上（AWS Provider 5.x、S3 バックエンド＋`use_lockfile` によるロック） |
| コンピュート | AWS Lambda（Python）、Amazon EC2（user_data による自律実行・自己 terminate） |
| ストレージ | Amazon S3（入力・出力・CloudTrail ログ・Terraform state） |
| 通知 | Amazon SES（メール）、Amazon SNS の SMS 直接 publish |
| 権限 | IAM（用途別ユーザー＋AssumeRole による最小権限、S3 の Deny フェンス） |
| 監視・監査 | Amazon CloudWatch Logs（CloudWatch Agent）、AWS CloudTrail |
| 運用スクリプト | bash（AWS CLI v2） |

## ディレクトリ構成

```
.
├── README.md            本書
├── CLAUDE.md            開発時に Claude Code へ与えていた指示（公開版向けに調整）
├── LICENSE              MIT License
├── docs/                設計・運用・用語・Terraform 引数リファレンス・構成図（SVG）
├── infra/               Terraform ルートモジュール（本体。VPC・S3・IAM・Lambda・監視）
│   ├── lambda/          Lambda 関数（lambda_function.py）と EC2 の user_data テンプレート
│   ├── bootstrap/       構築ロール ts-030-role-build を作る別ルートモジュール（初回1回）
│   └── backend/         state 用 S3 バケットを作る別ルートモジュール（常設）
└── tool/                運用スクリプト（投入・状態確認・結果取得・削除・EC2 上のジョブ）
```

## セットアップの要点

実際に構築する場合は、次の点に注意してください（詳細は [docs/運用ユーザーと再作成手順.md](docs/運用ユーザーと再作成手順.md)）。

1. ダミー値を自分の環境の値に書き換えます。
   - `infra/terraform.tfvars`・`infra/backend/terraform.tfvars` の `aws_account_id`
   - `infra/provider.tf` の `backend "s3"` ブロック（変数が使えないため直書き）の `role_arn` とバケット名
   - S3 バケット名はグローバルに一意である必要があるため、`ts-030-` のままでは作成できない場合があります。
2. AWS CLI のプロファイル（構築用・データ運用用・参照用）を `~/.aws/config` に用意します。
3. 作成順は `infra/bootstrap` → `infra/backend` → `infra`、破棄は `infra` → `infra/bootstrap` です。ルートモジュールごとに `terraform init` が必要です。
4. SES の email identity は手動で登録します。
5. 既定のインスタンスタイプ `c6i.4xlarge` は高額です。実行前に `run.conf` の `instance_type` を確認してください。

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
- メールアドレス・電話番号を含むため、実際の run.conf は `work/`（`.gitignore` 済み。公開版には含めていません）に置きます。

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

---

## ライセンス

[MIT License](LICENSE) で公開しています。Copyright (c) 2026 Tsystem

## 免責事項

- 本リポジトリのコード・文書は**現状のまま（AS IS）**提供するもので、動作・正確性・安全性について一切保証しません。利用によって生じたいかなる損害についても、作者は責任を負いません。
- 本リポジトリのコードを実行すると、AWS 上にリソース（EC2・S3・Lambda・CloudTrail など）が作成され、**AWS の利用料金が発生します**。料金は利用者の負担です。不要になったリソースは必ず削除してください。
- 公開版は、実際に稼働させた実装とは一致しない場合があります。
- アカウント ID・メールアドレス・電話番号・リソース ID などはダミー値です。そのままでは動作しないため、利用者自身の環境の値に書き換えてください。
- 本リポジトリは個人のポートフォリオであり、AWS（Amazon Web Services）・HashiCorp を含む第三者とは関係ありません。記載の製品名・サービス名は各社の商標または登録商標です。
