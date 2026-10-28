# `aws_internet_gateway` 設定可能キー（Argument Reference）
<!-- Last updated: 2026-09-22 18:02:53（設定例の見出しコメントをコードに合わせ、文体を統一） -->

Terraform AWS Provider の公式ドキュメント（最新版）に基づく、`resource "aws_internet_gateway"`（インターネットゲートウェイ＝IGW）で設定可能なキー（引数）の一覧です。

`aws_internet_gateway` は引数が非常に少ない、シンプルなリソースです。

> 注記: 本一覧は **AWS Provider 最新版** の Argument Reference に基づいています。`required_providers` で固定しているプロバイダーバージョンによって、引数の有無や挙動に差異が出る可能性があります。

---

## 1. 設定可能なキー（引数）

| キー | 必須/任意 | 説明 |
|---|---|---|
| `vpc_id` | 任意※ | IGW をアタッチする対象の VPC の ID。 |
| `region` | 任意 | このリソースを管理するリージョン。指定しない場合は provider 設定のリージョンが既定値。（近年追加されたマルチリージョン用引数） |
| `tags` | 任意 | リソースに付与するタグのマップ。provider の `default_tags` がある場合、キーが一致するものは上書き。 |

> ※ `vpc_id` について: 現行の Provider では **任意（Optional）** です。これは「VPC に未アタッチの IGW を作成し、後から `aws_internet_gateway_attachment` リソースで別途アタッチする」構成も取れるためです。ただし実運用では、下記の設定例のように IGW 作成時に `vpc_id` を指定して同時にアタッチするのが一般的です。
>
> （補足：本プロジェクトの固定バージョン `~> 5.0`（実バージョン `5.100.0`）でも `vpc_id` は Optional です（2026-09-22、`terraform providers schema -json` で確認）。）

---

## 2. Attribute（参照のみ・設定不可）

以下は作成後に出力される値であり、引数として設定はできません（参照専用）。

| Attribute | 説明 |
|---|---|
| `id` | IGW の ID（例: `igw-c0a643a9`）。ルートテーブルの `gateway_id` などで参照します。 |
| `arn` | IGW の Amazon リソースネーム（ARN）。 |
| `owner_id` | IGW を所有する AWS アカウントの ID。 |
| `tags_all` | provider の `default_tags` を含む、リソースに割り当てられた全タグのマップ。 |

---

## 3. 関連リソース・依存関係の注意

- **`aws_internet_gateway_attachment`** … IGW と VPC のアタッチを `vpc_id` を使わず独立したリソースとして管理したい場合に使用します。
- **依存関係（`depends_on`）** … 公式ドキュメントでは、インターネット接続を必要とする EC2 インスタンスや Elastic IP（EIP）が IGW に依存することを明示するため、`depends_on` の付与が推奨されています。IGW のアタッチ完了前にインスタンス起動・EIP 関連付けが走るのを防ぐためです。

```hcl
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
}

resource "aws_instance" "foo" {
  # ... 他の引数 ...
  depends_on = [aws_internet_gateway.main]   # IGW のアタッチ完了を待つ
}
```

- **ルートテーブルとの組み合わせ** … IGW を作っただけではインターネット通信はできません。ルートテーブルにデフォルトルート（`0.0.0.0/0` → IGW）を設定して、はじめてパブリック通信が成立します。

```hcl
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"               # 全宛先（デフォルトルート）
    gateway_id = aws_internet_gateway.main.id   # IGW へ向ける
  }
}
```

---

## 4. 設定例（参考）

本プロジェクトの `infra/network.tf` の構成です。

```hcl
# -----------------------------------------------------------------
# インターネットゲートウェイ
#   VPC にアタッチする（vpc_id 指定によりアタッチも同時に行われる）
# -----------------------------------------------------------------
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id                 # アタッチ先の VPC（aws_vpc.main を参照）

  tags = {
    Name = "${var.prj_prefix}-igw-010"     # VPC と同じ命名規則に合わせたタグ
  }
}
```
