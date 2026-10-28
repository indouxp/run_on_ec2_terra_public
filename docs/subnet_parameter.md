# `aws_subnet` 設定可能キー（Argument Reference）
<!-- Last updated: 2026-09-22 18:02:53（設定例の見出しコメントをコードに合わせ、文体を統一） -->

Terraform AWS Provider の公式ドキュメント（最新版）に基づく、`resource "aws_subnet"` で設定可能なキー（引数）の一覧です。用途ごとにグループ分けしています。

> 注記: 本一覧は **AWS Provider 最新版** の Argument Reference に基づいています。`region` や Outpost 系（`customer_owned_ipv4_pool` / `map_customer_owned_ip_on_launch`）の一部は、ドキュメント本文の該当行を直接確認できていない項目があり、表内にコメントを付けています。`required_providers` で固定しているプロバイダーバージョンによって、引数の有無や挙動に差異が出る可能性があります。

---

## 基本（必須・配置）

| キー | 必須/任意 | 説明 |
|---|---|---|
| `vpc_id` | **必須** | サブネットを作成する対象の VPC の ID。 |
| `cidr_block` | 任意※ | サブネットの IPv4 CIDR ブロック。（※ IPv6 専用サブネット（`ipv6_native = true`）の場合などは省略可） |
| `availability_zone` | 任意 | サブネットを配置する AZ（アベイラビリティーゾーン）。 |
| `availability_zone_id` | 任意 | サブネットの AZ ID。`availability_zone` の代わりに ID で指定する場合に使用。 |
| `region` | 任意 | このリソースを管理するリージョン。指定しない場合は provider 設定のリージョンが既定値。（近年追加されたマルチリージョン用引数） |

---

## IPv4 のパブリック IP / Outpost

| キー | 既定値 | 説明 |
|---|---|---|
| `map_public_ip_on_launch` | `false` | true にすると、このサブネットで起動したインスタンスにパブリック IP アドレスを割り当てます。パブリックサブネットで true にします。 |
| `outpost_arn` | - | Outpost の Amazon リソースネーム（ARN）。AWS Outposts 上にサブネットを作る場合に指定。 |
| `customer_owned_ipv4_pool` | - | Outpost 利用時の、顧客所有 IPv4 アドレスプール（CoIP）の ID。※ドキュメント本文の該当行は未確認（Outpost 関連の標準引数という前提）。 |
| `map_customer_owned_ip_on_launch` | `false` | 起動インスタンスに顧客所有 IP（CoIP）を割り当てるか。`customer_owned_ipv4_pool` とセットで使用。※ドキュメント本文の該当行は未確認。 |

---

## IPv6 関連

| キー | 既定値 | 説明 |
|---|---|---|
| `ipv6_cidr_block` | - | サブネットの IPv6 ネットワーク範囲（CIDR 表記）。サブネットサイズは /64 プレフィックス長である必要があります。 |
| `assign_ipv6_address_on_creation` | `false` | 起動したインスタンスに IPv6 アドレスを自動割り当てするか。`ipv6_cidr_block` が関連付けられている必要があります。 |
| `ipv6_native` | `false` | IPv6 専用サブネット（IPv4 を持たない）にするか。true にする場合は `cidr_block` を指定しません。 |
| `enable_dns64` | `false` | このサブネットの Amazon 提供 DNS リゾルバへの DNS クエリに対し、IPv4 専用宛先向けの合成 IPv6 アドレスを返すか（DNS64）。`ipv6_cidr_block` が必要。 |

---

## インスタンスのホスト名・DNS 応答

| キー | 既定値 | 説明 |
|---|---|---|
| `private_dns_hostname_type_on_launch` | - | 起動時にインスタンスへ割り当てるホスト名の種類。IPv6 専用サブネットではインスタンス ID ベースが必須。デュアルスタック／IPv4 専用ではインスタンスの IPv4 アドレスかインスタンス ID かを指定できます。有効値: `ip-name`, `resource-name`。 |
| `enable_resource_name_dns_a_record_on_launch` | `false` | インスタンスのホスト名に対する DNS クエリに DNS A レコードで応答するか。 |
| `enable_resource_name_dns_aaaa_record_on_launch` | `false` | インスタンスのホスト名に対する DNS クエリに DNS AAAA レコードで応答するか。`ipv6_cidr_block` が必要。 |
| `enable_lni_at_device_index` | - | このサブネットのローカルネットワークインターフェイス（LNI）のデバイス位置。例えば 1 は eth1（セカンダリ）。LNI はプライマリ（eth0）にはできません。 |

---

## タグ

| キー | 説明 |
|---|---|
| `tags` | リソースに付与するタグのマップ。provider の `default_tags` がある場合、キーが一致するものは上書き。 |

---

## 補足: Attribute（参照のみ・設定不可）

以下は作成後に出力される値であり、引数として設定はできません（参照専用）。

| Attribute | 説明 |
|---|---|
| `arn` | サブネットの ARN。 |
| `id` | サブネットの ID。 |
| `owner_id` | サブネットを所有する AWS アカウントの ID。 |
| `ipv6_cidr_block_association_id` | IPv6 CIDR ブロックの関連付け ID。 |
| `tags_all` | provider の `default_tags` を含む、リソースに割り当てられた全タグのマップ。 |

---

## 設定例（参考）

本プロジェクトの `infra/network.tf` の構成です。行末のコメントは説明用に付け加えたものです。

```hcl
# -----------------------------------------------------------------
# サブネット
#   VPC 内に単一のパブリックサブネットを作成する
# -----------------------------------------------------------------
resource "aws_subnet" "main" {
  vpc_id            = aws_vpc.main.id        # 紐づく VPC の ID（aws_vpc.main を参照）
  cidr_block        = var.subnet_cidr        # サブネットの IPv4 CIDR（変数で外出し）
  availability_zone = var.availability_zone  # 配置する AZ（ap-northeast-1a）

  tags = {
    Name = "${var.prj_prefix}-subnet-010"    # VPC と同じ命名規則に合わせたタグ
  }
}
```

> 本プロジェクトは `map_public_ip_on_launch` を指定しません（既定 `false`）。パブリック IP は起動 Lambda が RunInstances の `NetworkInterfaces[].AssociatePublicIpAddress = True` で付与します（`infra/lambda/lambda_function.py`）。
