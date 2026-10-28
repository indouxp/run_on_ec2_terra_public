# run_on_ec2_terra（public 版）
<!-- Last updated: 2026-10-28 09:30:00（公開版向けに再構成：個人情報・固有値のマスク、非公開ファイルへの言及を削除） -->

## プロジェクト概要
run_on_ec2_terra の public 版です。
run_on_ec2_terra を GitHub 上にポートフォリオとして公開します。
Public で公開するために、個人情報を省いています。
ポートフォリオとしての公開で、実装とは一致していません。

以下は、開発時に Claude Code へ与えていた指示（CLAUDE.md）を公開版向けに調整したものです。
  run_on_ec2 を Terraform で書き直し、ブラッシュアップします。

## 更新対象文書

都度、文書一覧、用語一覧は更新するようにして下さい。

## リソース名

AWSリソースを作成する時、このプロジェクトの場合は、ts-030-をプレフィックスとしてください。
タグとして、Projectをts-030としてください。

## リポジトリ構成

| パス | 役割 |
|------|------|
| `infra/` | フェーズ2 本体の Terraform ルートモジュール（フラット構成・モジュール未使用） |
| `infra/bootstrap/` | 構築ロール `ts-030-role-build` を作成する別ルートモジュール（state も init も `infra/` とは独立）。初回1回だけ apply |
| `infra/backend/` | `infra/` の state を置く S3 バケット `ts-030-bkt-tfstate` を作成する別ルートモジュール（構築ロールで apply、`prevent_destroy`）。全削除・再構築の対象外で常設 |
| `infra/lambda/` | Lambda 起動関数のソース（`lambda_function.py`・`user_data_template.sh`）。元プロジェクトからの実体コピー。`archive_file` で `infra/build/` に zip 化（build/ は ignore） |
| `docs/` | 設計・手順・用語・引数リファレンス（`*_parameter.md`）等のドキュメント |
| `tool/` | 運用スクリプト（`upl-run.sh`＝in へ投入し EC2 起動／`pop-s3.sh`＝out の結果取得・検証後削除／`del-s3.sh`＝in/out 全削除／`get-now.sh`＝状態確認／`run.sh`＝EC2 上で実行するジョブ）、タグベースのリソース情報取得、AWS CLI v2・Terraform のインストール。`skl078.sh`（シェル雛形）は公開版には含めない |
| `README.md` | プロジェクト概要・元プロジェクト（run_on_ec2）の説明 |

### infra/*.tf の分担

| ファイル | 内容 |
|------|------|
| `provider.tf` | AssumeRole 構成・`default_tags`・`backend "s3"`（`ts-030-bkt-tfstate`、`use_lockfile`）。`required_version = ">= 1.10"`。provider は aws `~> 5.0` / http `~> 3.0` / archive `~> 2.0`（実バージョン 5.100.0 / 3.6.0 / 2.8.0） |
| `variables.tf` / `terraform.tfvars` | 変数定義と実値。**tfvars が variables.tf の既定値を上書きする**ため、既定値を変えたら tfvars も確認する |
| `network.tf` | VPC / Subnet / IGW / ルートテーブル（WBS 2.1） |
| `security.tf` | SG と個別ルール。SSH は `data "http"` で取得した実行元グローバル IP /32 のみ許可（WBS 2.2） |
| `storage.tf` | S3 in/out（for_each）・暗号化・PAB・ライフサイクル・Lambda トリガー・Deny フェンス型バケットポリシー（WBS 2.3/2.4e） |
| `iam.tf` | Lambda/EC2 実行ロール・Instance Profile・データ運用ロール `ts-030-role-operate`（WBS 2.4） |
| `compute.tf` | Lambda 起動関数 `lmd-010`（WBS 2.5） |
| `monitoring.tf` | CloudWatch Logs（ロググループ3種＋メトリクスフィルタ）・CloudTrail（証跡＋ログ用バケット）（WBS 2.8）。※ Lambda は `logging_config` 未指定のため、実際のログは Lambda 既定の `/aws/lambda/ts-030-lmd-010`（Terraform 管理外）に出て、`ts-030-log-lambda-010` は未使用（改善対象 B-6） |
| `outputs.tf` | 出力値 |
| `info-ts-030.sh` | `ts-030-` の全ロール（本体・管理ポリシー・インラインポリシー）とネットワーク（IGW/RT/VPC/Subnet）の設定を JSON/YAML に出力する調査スクリプト（生成物は ignore。YAML 出力には python3-yaml が必要） |

## 認証・apply 手順

- 管理者 `ts-usr-admin` は常用しない。用途別に絞った3ユーザーで運用する（詳細: `docs/ユーザーとロール一覧.md` / `docs/運用ユーザーと再作成手順.md`）。ユーザーは `ts-030-` プレフィックス（`ts-usr-*` 共用ユーザーのみ例外）。IAM グループは未使用。
  - `infra/bootstrap/`（構築ロールの作成・削除）: プロファイル `ts-030-usr-role-admin`（`ts-030-*` ロールの IAM 操作のみ）。`bootstrap/variables.tf` の `role_admin_profile`。
  - `infra/`（リソース作成・削除）: プロファイル `ts-030-usr-build`（`sts:AssumeRole` のみ）が `ts-030-role-build` を AssumeRole。`infra/variables.tf` の `assume_profile`。
  - データ運用（in/out の投入・取得・削除）: `~/.aws/config` のプロファイル `ts-030-role-operate`（`role_arn` ＋ `source_profile = ts-030-usr-operate`。ユーザー自身は `sts:AssumeRole` のみ）経由で `tool/upl-run.sh`・`pop-s3.sh`・`del-s3.sh`・`get-now.sh` を実行（CLI が自動で AssumeRole）。構築権限は持たず、EC2・ログも参照できない。
  - 実機確認（参照のみ）: プロファイル `ts-usr-readonly`。`info-ts-030.sh` や describe 系の確認に使う。`terraform plan` は実行不可（構築ロールのプロファイルで行う）。in/out バケットの一覧・取得は Deny フェンスで不可（`tool/*.sh` は S3 を `ts-030-role-operate`、EC2・ログを `ts-usr-readonly` で参照する）。
- プロファイルは provider の `profile` 設定で参照するため、`AWS_PROFILE` 環境変数は不要。`apply.sh` / `destroy.sh` を使うと `apply_<日時>.log` / `destroy_<日時>.log` にログを残す（ignore 済み）。
- `default_tags` で `Project=ts-030` を全リソースに自動付与する。個別リソースに `Project` タグを手書きしない。
- ルートモジュールごとに `terraform init` が必要（`infra/`・`infra/bootstrap/`・`infra/backend/` で別々）。
- state の置き場所: `infra/` は S3（`ts-030-bkt-tfstate` の `infra/terraform.tfstate`、`use_lockfile` でロック）。`infra/bootstrap/` と `infra/backend/` はローカル（リソースが少なく import で復旧可能）。
- 破棄・再作成の順序: 破棄は `infra` → `bootstrap`、作成は `bootstrap` → `infra`。`infra/backend/` は対象外（破棄しない）。bootstrap を破棄している間は構築ロールが無いため、`infra` の state も読めない。
- `infra/bootstrap` の apply は、Claude が `terraform plan -out=tfplan` → `terraform apply tfplan` で実行できる（2026-09-22 に権限削減の apply で確認）。ただし IAM 権限を広げる変更は auto mode の安全判定で止められることがある（同日、権限追加のコミットで発生）。止められた場合はユーザーが手動で実行する。できないと決めつけず、まず試す。
- 変更後の検証手順: `terraform fmt` → `validate` → `plan`（差分の意味を確認）→ `apply` → 再 `plan` で No changes（冪等性）→ CLI で実機確認。

## 構築上の注意（過去の不具合から）

- Terraform は apply 後の read-after-write で CLI 版より広い読取権限（`Get*`/`List*`/`Describe*`）を要求する。新リソース追加時は `bootstrap/iam_build_role.tf` の構築ロール権限不足に注意（`docs/不具合一覧.md` BUG-001/002）。
- 削除系の権限も destroy で検証する。IAM ロール削除には `iam:ListInstanceProfilesForRole`、中身のあるバケットの `force_destroy` には `s3:DeleteObject`（バージョニング無効時）が必要（BUG-004）。destroy は必ず `destroy.sh` でログを残す。
- CloudTrail ログ用バケットは `force_destroy = true`。`terraform destroy` で監査ログも消える。
- 旧端末のディスク故障でローカル state を消失し import で復旧した（BUG-003）。再発防止として `infra/` の state は S3 に移行済み（改善対象 B-5）。
- S3 バケットポリシーの Deny フェンスで `s3:ListBucket` を拒否対象にする場合、承認 principal に `ts-030-role-build` を必ず含める。含めないと HeadBucket が 403 になり、Terraform がバケットを「削除済み」と誤認して全再作成を plan する。

## 設計上の決定事項（再検討しない限り前提とする）

- 終了処理は簡素化済み: 起動時 `InstanceInitiatedShutdownBehavior=terminate` で EC2 が自己 terminate する。終了 Lambda（lmd-020）・EventBridge ルール・role-lambda-020 は作らない（WBS 2.4c/2.6/2.7 廃止）。
- SNS トピックは作らない（SMS は電話番号へ直接 publish、Email は SES 直接送信のため未使用）。Lambda の `sns:Publish` は Resource=`"*"`。
- CloudWatch アラームは作らない。CloudWatch Logs の KMS 暗号化（S-1）は不要と判断済み。
- SES の email identity は Terraform 化せず手動で登録する。
- 既定のインスタンスタイプ c6i.4xlarge は高額。EC2 を実起動する（upl-run.sh を実行する）ときは事前にユーザーへ確認する。E2E（WBS 2.9）は 2026-09-22 に成功（自己 terminate・EBS 削除・SMS/メール着信を確認）。
- run.sh の実行時間は run.conf の `timeout`（秒、未指定時 21600）で打ち切る。止まらずに課金が続く事故の保険。
- バックグラウンド処理を起動するシェル（雛形 skl078.sh 準拠の run.sh 等）は、その標準エラーもファイルへ向ける。tee のパイプを握ったままにすると、終了時の tee 待ちで止まる（BUG-005、bash 5 系で発生）。

## Git・state・ログの扱い

- このリポジトリは **public**（ポートフォリオ公開版）。非公開の開発用リポジトリからコピーし、個人情報・固有値をマスクしている。
- アカウント ID・メールアドレス・電話番号・リソース ID 等は例示用のダミー値（`123456789012`、`user@example.com`、`vpc-0123456789abcdef0` 等）に置き換え済み。新たにログや出力を載せる場合も、同様にマスクしてからコミットする。
- **アクセスキー・シークレットキー等の認証情報はコミットしない**。
- `*.tfstate` と `**/.terraform/` は `.gitignore` 済み。state は機微情報を含むため push しない。
- `infra/terraform.tfvars` は追跡対象（ダミー値のみを置く）。
- コミットメッセージは `feat(infra): ...` / `docs: ...` 形式。WBS 番号がある場合は記載する。

## public 化の方針

- 公開版は非公開リポジトリを直接公開せず、`_public` を付けた**コピー**側で個人情報・固有値をマスクして作成した。
- 端末ログ（apply ログ等）とセッション記録は公開版に含めない。

## セッション継続

- 作業の進め方は `docs/WBS.md`、未対応の改善検討は `docs/改善対象.md`、不具合の記録は `docs/不具合一覧.md` を参照する。
