# =================================================================
# セキュリティグループ（WBS No.2.2）
#   SG 本体 / SSH インバウンドルール / アウトバウンド全許可ルール
#   受信は SSH のみ（実行元グローバル IP /32 限定）、送信は全許可
# Last updated: 2026-09-22 17:17:32
# =================================================================

# -----------------------------------------------------------------
# 実行元グローバル IP の取得
#   terraform apply を実行するマシンのグローバル IP を取得する。
#   checkip.amazonaws.com は送信元 IP を平文で返すため、その本文を利用する。
#   AWS 側ではなく手元マシンから取得される点に注意。
# -----------------------------------------------------------------
data "http" "myip" {
  url = "https://checkip.amazonaws.com"
}

# -----------------------------------------------------------------
# セキュリティグループ本体
#   インバウンドは既定でなし（下の ingress ルールで SSH のみ許可）、
#   アウトバウンドは下の egress ルールで全許可とする。
# -----------------------------------------------------------------
resource "aws_security_group" "main" {
  name        = "${var.prj_prefix}-sg-010"
  description = "For S3 trigger type shell script auto execution system"
  vpc_id      = aws_vpc.main.id

  tags = {
    Name = "${var.prj_prefix}-sg-010"
  }
}

# -----------------------------------------------------------------
# インバウンド: SSH(TCP 22) を実行元グローバル IP /32 のみ許可
#   個別ルールリソースで定義することで、ルール変更時に
#   SG 本体を作り直さずに済む。
# -----------------------------------------------------------------
resource "aws_vpc_security_group_ingress_rule" "ssh" {
  security_group_id = aws_security_group.main.id
  cidr_ipv4         = "${chomp(data.http.myip.response_body)}/32"
  ip_protocol       = "tcp"
  from_port         = 22
  to_port           = 22

  tags = {
    Name = "${var.prj_prefix}-sgr-ssh-010"
  }
}

# -----------------------------------------------------------------
# アウトバウンド: 全許可（SG 既定の全許可ルールを明示的に定義）
#   EC2 は外部から接続を受けず（受信は SSH のみ）、S3/SNS 等へ
#   外向き通信するため、送信は全プロトコル・全宛先を許可する。
# -----------------------------------------------------------------
resource "aws_vpc_security_group_egress_rule" "all" {
  security_group_id = aws_security_group.main.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1" # 全プロトコル

  tags = {
    Name = "${var.prj_prefix}-sgr-egress-010"
  }
}
