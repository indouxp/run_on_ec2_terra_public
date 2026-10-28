# `aws_route_table` 設定可能キー（Argument Reference）
<!-- Last updated: 2026-09-22 18:02:53（設定例のコメントをコードに合わせ、文体を統一） -->

Terraform AWS Provider の公式ドキュメント（最新版）に基づく、`resource "aws_route_table"`（ルートテーブル）で設定可能なキー（引数）の一覧です。

`aws_route_table` は、トップレベルの引数に加えて、内部に **`route` ブロック**（経路の定義）を持つ構造が特徴です。

> 注記: 本一覧は **AWS Provider 最新版** の Argument Reference に基づいています。`required_providers` で固定しているプロバイダーバージョンによって、引数の有無や挙動に差異が出る可能性があります。

---

## 1. トップレベルの引数

| キー | 必須/任意 | 説明 |
|---|---|---|
| `vpc_id` | **必須** | ルートテーブルを作成する対象の VPC の ID。 |
| `route` | 任意 | 経路（ルート）オブジェクトのリスト。キーは後述。**attribute-as-blocks モード**で処理されます。この引数を省略すると「既存ルートを無視する」と解釈されます。管理対象ルートをすべて削除するには空リスト `route = []` を指定します。 |
| `propagating_vgws` | 任意 | 経路伝播（propagation）させる仮想プライベートゲートウェイ（VGW）のリスト。 |
| `region` | 任意 | このリソースを管理するリージョン。指定しない場合は provider 設定のリージョンが既定値。 |
| `tags` | 任意 | リソースに付与するタグのマップ。provider の `default_tags` がある場合、キーが一致するものは上書き。 |

---

## 2. `route` ブロック内の引数

`route` ブロックは「どの宛先（destination）への通信を、どの出口（target）へ流すか」を 1 経路ずつ定義します。
**宛先（destination）から 1 つ、出口（target）から 1 つ**を指定するのが基本です。

### 2-1. 宛先（destination）— いずれか 1 つを必須で指定

| キー | 必須/任意 | 説明 |
|---|---|---|
| `cidr_block` | **必須**（宛先群の中で） | 経路の IPv4 CIDR ブロック。例: `0.0.0.0/0`（全宛先＝デフォルトルート）。 |
| `ipv6_cidr_block` | 任意 | 経路の IPv6 CIDR ブロック。例: `::/0`。 |
| `destination_prefix_list_id` | 任意 | マネージドプレフィックスリストを宛先とする場合の ID。 |

### 2-2. 出口（target）— いずれか 1 つを必須で指定

| キー | 説明 |
|---|---|
| `gateway_id` | VPC インターネットゲートウェイ、仮想プライベートゲートウェイ、または `local` の識別子。`local` ルートは作成不可だが、採用（adopt）・インポートは可能。 |
| `nat_gateway_id` | VPC NAT ゲートウェイの識別子。 |
| `egress_only_gateway_id` | VPC Egress Only インターネットゲートウェイ（IPv6 アウトバウンド専用）の識別子。 |
| `carrier_gateway_id` | キャリアゲートウェイの識別子。VPC が Wavelength Zone に関連付くサブネットを含む場合のみ使用可。 |
| `core_network_arn` | コアネットワーク（Cloud WAN）の ARN。 |
| `local_gateway_id` | Outpost のローカルゲートウェイの識別子。 |
| `network_interface_id` | EC2 ネットワークインターフェイス（ENI）の識別子。 |
| `transit_gateway_id` | EC2 Transit Gateway の識別子。 |
| `vpc_endpoint_id` | VPC エンドポイントの識別子。 |
| `vpc_peering_connection_id` | VPC ピアリング接続の識別子。 |

> 注意: VPC の CIDR ブロックを `local` にマッピングするデフォルト経路は**暗黙的に自動作成**され、明示的に指定することはできません。

---

## 3. Attribute（参照のみ・設定不可）

以下は作成後に出力される値であり、引数として設定はできません（参照専用）。

| Attribute | 説明 |
|---|---|
| `id` | ルートテーブルの ID（例: `rtb-4e616f6d69`）。サブネットとの関連付け（`aws_route_table_association`）などで参照します。 |
| `arn` | ルートテーブルの ARN。 |
| `owner_id` | ルートテーブルを所有する AWS アカウントの ID。 |
| `tags_all` | provider の `default_tags` を含む、リソースに割り当てられた全タグのマップ。 |

> 注記: route ブロックでは、**実際に入力した target のみ**が、作成後に読み取り可能な属性としてエクスポートされます。

---

## 4. 重要な注意点

- **`aws_route` リソースとの併用不可**: Terraform にはインライン `route` ブロックを持つ `aws_route_table` と、独立した `aws_route` リソースの両方があります。同一のルートテーブルに対して**両方を併用するとルール設定が競合し、上書きされる**ため、どちらか一方に統一します。
- **`gateway_id` と `nat_gateway_id` の取り違え**: AWS API は寛容なため、NAT の ID を `gateway_id` に指定しても作成自体は通ってしまいます。しかしその場合、設定ファイルと state の間で**恒久的な差分（permanent diff）**が発生します。差分が消えない場合は、まずこの取り違えを確認します。
- **`propagating_vgws` と `aws_vpn_gateway_route_propagation` の併用不可**: `propagating_vgws` を指定すると、明示列挙されていない伝播ゲートウェイは削除されます。別リソースで経路伝播を定義する場合は `propagating_vgws` を省略します。
- **ルートテーブル単体ではトラフィックは流れません**: 作成後、`aws_route_table_association` で**サブネット（または IGW）に関連付け**て、はじめて経路が有効になります。

---

## 5. 設定例（参考）

本プロジェクトの `infra/network.tf` の構成です。VPC のメインルートテーブルは編集せず、管理範囲を明確にするため専用ルートテーブルを新規作成しています。行末のコメントは説明用に付け加えたものです。

```hcl
# -----------------------------------------------------------------
# ルートテーブル
#   VPC のメインルートテーブルは編集せず、管理範囲を明確にするため
#   専用ルートテーブルを新規作成する。
#   0.0.0.0/0 を IGW へ向けるデフォルトルートを持たせる。
# -----------------------------------------------------------------
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id                       # 対象の VPC（aws_vpc.main を参照）

  route {
    cidr_block = "0.0.0.0/0"                      # 宛先：全 IPv4（デフォルトルート）
    gateway_id = aws_internet_gateway.main.id     # 出口：インターネットゲートウェイ
  }

  tags = {
    Name = "${var.prj_prefix}-rtt-010"            # VPC と同じ命名規則に合わせたタグ
  }
}

# -----------------------------------------------------------------
# ルートテーブルの関連付け
#   作成したサブネットを上記ルートテーブルに紐付け、
#   サブネットからインターネットへ到達できるようにする
# -----------------------------------------------------------------
resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.main.id             # 関連付けるサブネット
  route_table_id = aws_route_table.public.id      # 上で作成したルートテーブル
}
```
