# `aws_vpc` 設定可能キー（Argument Reference）
<!-- Last updated: 2026-09-22 18:02:53（設定例の見出しコメントをコードに合わせ、文体を統一） -->

Terraform AWS Provider の公式ドキュメント（最新版）に基づく、`resource "aws_vpc"` で設定可能なキー（引数）の一覧です。

> 注記: 本一覧は **AWS Provider 最新版** の Argument Reference に基づいています。`required_providers` で固定しているプロバイダーバージョンによっては、引数の有無や挙動に差異が出る可能性があります（古いバージョンでは `enable_classiclink` など、現在は廃止された引数が存在した時期もあります）。

---

## 設定可能なキー（引数）

| キー | 必須/任意 | 説明 |
|---|---|---|
| `region` | 任意 | このリソースを管理するリージョン。指定しない場合は provider 設定のリージョンが既定値。 |
| `cidr_block` | 任意 | VPC の IPv4 CIDR ブロック。明示指定するか、`ipv4_netmask_length` を使って IPAM から導出可能。 |
| `instance_tenancy` | 任意 | VPC で起動するインスタンスのテナンシー。既定は `default`。もう一方の選択肢は `dedicated`（専用テナンシー、追加課金あり）。 |
| `ipv4_ipam_pool_id` | 任意 | この VPC の CIDR 割り当てに使う IPv4 IPAM プールの ID。 |
| `ipv4_netmask_length` | 任意 | この VPC に割り当てる IPv4 CIDR のネットマスク長。`ipv4_ipam_pool_id` の指定が必要。 |
| `ipv6_cidr_block` | 任意 | IPAM プールから要求する IPv6 CIDR ブロック。明示指定または `ipv6_netmask_length` から導出可能。 |
| `ipv6_ipam_pool_id` | 任意 | IPv6 プール用の IPAM プール ID。`assign_generated_ipv6_cidr_block` と競合。 |
| `ipv6_netmask_length` | 任意 | IPAM プールから要求するネットマスク長。`ipv6_cidr_block` と競合。有効値は 44〜60（4 刻み）。 |
| `ipv6_cidr_block_network_border_group` | 任意 | IPv6 CIDR をパブリックアドレスとして広告するネットワークボーダーグループの制限（LocalZones など）。既定は VPC のリージョン。 |
| `enable_dns_support` | 任意 | VPC の DNS 解決の有効/無効。既定は `true`。 |
| `enable_dns_hostnames` | 任意 | VPC の DNS ホスト名の有効/無効。既定は `false`。 |
| `enable_network_address_usage_metrics` | 任意 | VPC の Network Address Usage メトリクスの有効/無効。既定は `false`。 |
| `assign_generated_ipv6_cidr_block` | 任意 | Amazon 提供の /56 IPv6 CIDR ブロックを要求。範囲やサイズは指定不可。既定は `false`。`ipv6_ipam_pool_id` と競合。 |
| `tags` | 任意 | リソースに付与するタグのマップ。provider の `default_tags` がある場合、キーが一致するものは上書き。 |

---

## 補足: Attribute（参照のみ・設定不可）

以下は作成後に出力される値であり、引数として設定はできません（参照専用）。

| Attribute | 説明 |
|---|---|
| `arn` | VPC の Amazon リソースネーム（ARN）。 |
| `id` | VPC の ID。 |
| `instance_tenancy` | VPC 内で起動するインスタンスのテナンシー。 |
| `dhcp_options_id` | VPC の DHCP オプションセット ID。 |
| `enable_dns_support` | VPC の DNS 解決が有効かどうか。 |
| `enable_network_address_usage_metrics` | Network Address Usage メトリクスが有効かどうか。 |
| `enable_dns_hostnames` | VPC の DNS ホスト名が有効かどうか。 |
| `main_route_table_id` | この VPC のメインルートテーブルの ID。 |
| `default_network_acl_id` | VPC 作成時に既定で作られるネットワーク ACL の ID。 |
| `default_security_group_id` | VPC 作成時に既定で作られるセキュリティグループの ID。 |
| `default_route_table_id` | VPC 作成時に既定で作られるルートテーブルの ID。 |
| `ipv6_association_id` | IPv6 CIDR ブロックの関連付け ID。 |
| `ipv6_cidr_block_network_border_group` | ネットワークボーダーグループのゾーン名。 |
| `owner_id` | VPC を所有する AWS アカウントの ID。 |
| `tags_all` | provider の `default_tags` を含む、リソースに割り当てられた全タグのマップ。 |

---

## 設定例（参考）

本プロジェクトの `infra/network.tf` の構成です（プロバイダ （本プロジェクトの固定バージョン `~> 5.0`、`.terraform.lock.hcl` 上の実バージョン `5.100.0`）。行末のコメントは説明用に付け加えたものです）。

```hcl
# -----------------------------------------------------------------
# VPC
#   DNS ホスト名・DNS 解決を有効化する
# -----------------------------------------------------------------
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr               # VPC の IPv4 CIDR（変数で外出し）
  enable_dns_hostnames = true                       # DNS ホスト名を有効化
  enable_dns_support   = true                       # DNS 解決を有効化

  tags = {
    Name = "${var.prj_prefix}-vpc-010"              # プロジェクト接頭辞を付与したタグ
  }
}
```
