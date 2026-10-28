#!/bin/bash
#===============================================================================
# aws-describe-tagged-resources.sh
#
# 指定タグを持つAWSリソース + 名前プレフィクス一致リソース（IAM含む）の
# 設定値をすべて取得し、Markdown形式で出力する汎用スクリプト。
# 参考として、リージョン内の SES identity もすべて出力する。
#
# Last updated: 2026-09-21 21:20:54
#
# 使い方:
#   ./aws-describe-tagged-resources.sh \
#     -k Project -v ts-030 -p ts-usr-readonly -r ap-northeast-1 \
#     -i ts-030 -o output.md
#
# 制約:
#   - IAMリソースはresourcegroupstaggingapiで取得不可のため、
#     -i で指定した名前プレフィクスで別途検索する。
#   - -i 指定時は、タグの付け忘れに備えて EC2/S3/Lambda/Logs/CloudTrail/SNS も
#     名前プレフィクスで検索し、タグ検索の結果と合わせて（重複除去して）出力する。
#     EC2 は Name タグ、その他はリソース名で判定する。
#   - SES identity はメールアドレス等で名前判定できないため、全件を参考出力する。
#   - 検索対象は -r で指定した1リージョンのみ（IAM はグローバル）。
#   - サポート外のリソースタイプはARNとともにスキップログを出力する。
#===============================================================================

set -euo pipefail

#--- デフォルト値 ---
TAG_KEY=""            # タグキー（必須）
TAG_VALUE=""          # タグ値（必須）
PROFILE=""            # AWS CLIプロファイル（必須）
REGION="ap-northeast-1"  # AWSリージョン
IAM_PREFIX=""         # 名前プレフィクス（任意）。IAM検索と名前検索に使う
OUTPUT_FILE=""        # 出力ファイルパス（必須）
ACCOUNT_ID_MASK="[ACCOUNT_ID]"  # アカウントIDマスク文字列

#--- 使用方法 ---
usage() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS]

Options:
  -k TAG_KEY       タグキー（必須）
  -v TAG_VALUE     タグ値（必須）
  -p PROFILE       AWS CLIプロファイル名（必須）
  -r REGION        AWSリージョン（デフォルト: ap-northeast-1）
  -i IAM_PREFIX    名前プレフィクス（任意）。IAM検索と、タグ付け漏れに備えた名前検索に使う
  -o OUTPUT_FILE   出力ファイルパス（必須）
  -h               この使用方法を表示

Example:
  $(basename "$0") -k Project -v ts-030 -p ts-usr-readonly -r ap-northeast-1 -i ts-030 -o output.md
EOF
    exit 1
}

#--- 引数解析 ---
while getopts "k:v:p:r:i:o:h" opt; do
    case "$opt" in
        k) TAG_KEY="$OPTARG" ;;       # タグキー
        v) TAG_VALUE="$OPTARG" ;;     # タグ値
        p) PROFILE="$OPTARG" ;;       # AWS CLIプロファイル
        r) REGION="$OPTARG" ;;        # リージョン
        i) IAM_PREFIX="$OPTARG" ;;    # IAMプレフィクス
        o) OUTPUT_FILE="$OPTARG" ;;   # 出力先
        h) usage ;;
        *) usage ;;
    esac
done

# 必須パラメータチェック
if [[ -z "$TAG_KEY" || -z "$TAG_VALUE" || -z "$PROFILE" || -z "$OUTPUT_FILE" ]]; then
    echo "ERROR: -k, -v, -p, -o は必須パラメータです。" >&2
    usage
fi

#--- AWSアカウントIDを取得（マスク処理用） ---
# STSでアカウントIDを取得し、出力時にマスクする
ACTUAL_ACCOUNT_ID=$(aws sts get-caller-identity \
    --profile "$PROFILE" \
    --output json \
    | jq -r '.Account')

#--- マスク処理関数 ---
# 引数: マスク対象テキスト（stdin）
mask_account_id() {
    sed "s/${ACTUAL_ACCOUNT_ID}/${ACCOUNT_ID_MASK}/g"
}

#--- 共通AWS CLIオプション ---
# --output json を明示（プロファイルのoutput設定に依存しない）
aws_cmd() {
    aws --profile "$PROFILE" --region "$REGION" --output json "$@"
}

# IAMはリージョン不要（グローバルサービス）
aws_iam() {
    aws --profile "$PROFILE" --output json iam "$@"
}

#--- Markdown出力ヘルパー ---
# 出力先ファイルへの追記
out() {
    echo "$@" >> "$OUTPUT_FILE"
}

# JSON をコードブロックとして出力（マスク処理付き）
# 引数: $1=出力するJSON文字列
out_json() {
    local json_data="$1"
    out '```json'
    echo "$json_data" | jq '.' 2>/dev/null | mask_account_id >> "$OUTPUT_FILE" \
        || echo "$json_data" | mask_account_id >> "$OUTPUT_FILE"
    out '```'
    out ""
}

# コマンドを実行し、成功時は見出し付きでJSONを出力する。
# 失敗時（未設定・権限不足等）は処理を止めず、エラー内容を注記として出力する。
# 引数: $1=見出し, $2以降=実行するコマンド
out_optional() {
    local title="$1"   # 出力する見出し
    shift
    local result       # コマンドの標準出力（成功時）または標準エラー（失敗時）
    out "#### ${title}"
    out ""
    if result=$("$@" 2>&1); then
        out_json "$result"
    else
        out "> 取得なし: $(echo "$result" | tail -n 1 | mask_account_id)"
        out ""
    fi
}

# 進捗表示（stderr）
log() {
    echo "[INFO] $*" >&2
}

# スキップログ（stderr + ファイル）
log_skip() {
    echo "[SKIP] $*" >&2
    out "> **SKIP**: $*"
    out ""
}

#===============================================================================
# EC2リソース describe関数群
# 各関数は、ARNからリソースIDを抽出し、対応するdescribeコマンドを実行する。
#===============================================================================

# VPCの設定値を取得
# 引数: $1=VPC ID (例: vpc-xxxxxxxxx)
describe_ec2_vpc() {
    local vpc_id="$1"
    log "EC2 VPC: $vpc_id"
    out "### VPC: \`$vpc_id\`"
    out ""

    # VPC本体
    local result
    result=$(aws_cmd ec2 describe-vpcs --vpc-ids "$vpc_id")
    out "#### VPC設定"
    out ""
    out_json "$result"

    # VPCに紐づくCIDRブロック（IPv6等の追加CIDR含む）
    local cidr_result
    cidr_result=$(aws_cmd ec2 describe-vpc-cidr-block-associations --filters "Name=vpc-id,Values=$vpc_id" 2>/dev/null) \
        && { out "#### CIDR Block Associations"; out ""; out_json "$cidr_result"; } \
        || true

    # VPC属性（DNS設定）
    for attr in enableDnsSupport enableDnsHostnames; do
        local attr_result
        attr_result=$(aws_cmd ec2 describe-vpc-attribute --vpc-id "$vpc_id" --attribute "$attr")
        out "#### VPC Attribute: \`$attr\`"
        out ""
        out_json "$attr_result"
    done
}

# サブネットの設定値を取得
# 引数: $1=Subnet ID (例: subnet-xxxxxxxxx)
describe_ec2_subnet() {
    local subnet_id="$1"
    log "EC2 Subnet: $subnet_id"
    out "### Subnet: \`$subnet_id\`"
    out ""
    local result
    result=$(aws_cmd ec2 describe-subnets --subnet-ids "$subnet_id")
    out_json "$result"
}

# インターネットゲートウェイの設定値を取得
# 引数: $1=IGW ID (例: igw-xxxxxxxxx)
describe_ec2_igw() {
    local igw_id="$1"
    log "EC2 InternetGateway: $igw_id"
    out "### Internet Gateway: \`$igw_id\`"
    out ""
    local result
    result=$(aws_cmd ec2 describe-internet-gateways --internet-gateway-ids "$igw_id")
    out_json "$result"
}

# ルートテーブルの設定値を取得
# 引数: $1=RouteTable ID (例: rtb-xxxxxxxxx)
describe_ec2_route_table() {
    local rtb_id="$1"
    log "EC2 RouteTable: $rtb_id"
    out "### Route Table: \`$rtb_id\`"
    out ""
    local result
    result=$(aws_cmd ec2 describe-route-tables --route-table-ids "$rtb_id")
    out_json "$result"
}

# セキュリティグループの設定値を取得
# 引数: $1=SecurityGroup ID (例: sg-xxxxxxxxx)
describe_ec2_security_group() {
    local sg_id="$1"
    log "EC2 SecurityGroup: $sg_id"
    out "### Security Group: \`$sg_id\`"
    out ""
    local result
    result=$(aws_cmd ec2 describe-security-groups --group-ids "$sg_id")
    out_json "$result"
}

# EC2インスタンスの設定値を取得
# 引数: $1=Instance ID (例: i-xxxxxxxxx)
describe_ec2_instance() {
    local instance_id="$1"
    log "EC2 Instance: $instance_id"
    out "### Instance: \`$instance_id\`"
    out ""
    local result
    result=$(aws_cmd ec2 describe-instances --instance-ids "$instance_id")
    out_json "$result"
}

# NATゲートウェイの設定値を取得
# 引数: $1=NATGateway ID (例: nat-xxxxxxxxx)
describe_ec2_natgateway() {
    local nat_id="$1"
    log "EC2 NATGateway: $nat_id"
    out "### NAT Gateway: \`$nat_id\`"
    out ""
    local result
    result=$(aws_cmd ec2 describe-nat-gateways --nat-gateway-ids "$nat_id")
    out_json "$result"
}

# Elastic IPの設定値を取得
# 引数: $1=Allocation ID (例: eipalloc-xxxxxxxxx)
describe_ec2_eip() {
    local alloc_id="$1"
    log "EC2 EIP: $alloc_id"
    out "### Elastic IP: \`$alloc_id\`"
    out ""
    local result
    result=$(aws_cmd ec2 describe-addresses --allocation-ids "$alloc_id")
    out_json "$result"
}

# ネットワークインターフェースの設定値を取得
# 引数: $1=ENI ID (例: eni-xxxxxxxxx)
describe_ec2_network_interface() {
    local eni_id="$1"
    log "EC2 NetworkInterface: $eni_id"
    out "### Network Interface: \`$eni_id\`"
    out ""
    local result
    result=$(aws_cmd ec2 describe-network-interfaces --network-interface-ids "$eni_id")
    out_json "$result"
}

# Network ACLの設定値を取得
# 引数: $1=NACL ID (例: acl-xxxxxxxxx)
describe_ec2_network_acl() {
    local nacl_id="$1"
    log "EC2 NetworkACL: $nacl_id"
    out "### Network ACL: \`$nacl_id\`"
    out ""
    local result
    result=$(aws_cmd ec2 describe-network-acls --network-acl-ids "$nacl_id")
    out_json "$result"
}

# EBSボリュームの設定値を取得
# 引数: $1=Volume ID (例: vol-xxxxxxxxx)
describe_ec2_volume() {
    local volume_id="$1"   # 対象ボリュームID
    log "EC2 Volume: $volume_id"
    out "### EBS Volume: \`$volume_id\`"
    out ""
    local result
    result=$(aws_cmd ec2 describe-volumes --volume-ids "$volume_id")
    out_json "$result"
}

#===============================================================================
# CloudWatch Logs / CloudTrail describe関数
#===============================================================================

# ロググループの設定値と、紐づくメトリクスフィルタを取得
# 引数: $1=ロググループ名
describe_logs_group() {
    local group_name="$1"   # 対象ロググループ名
    log "Logs LogGroup: $group_name"
    out "### CloudWatch Log Group: \`$group_name\`"
    out ""

    # プレフィクス検索のため、完全一致するものだけに絞る
    local result
    result=$(aws_cmd logs describe-log-groups --log-group-name-prefix "$group_name" \
        | jq --arg name "$group_name" '{logGroups: [.logGroups[] | select(.logGroupName == $name)]}')
    out "#### Log Group設定"
    out ""
    out_json "$result"

    # メトリクスフィルタ（タグ非対応のためタグ検索では出てこない）
    out_optional "Metric Filters" aws_cmd logs describe-metric-filters --log-group-name "$group_name"
}

# CloudTrail証跡の設定値・稼働状態・イベントセレクタを取得
# 引数: $1=証跡ARN（マルチリージョン証跡でも一意に指せるようARNを使う）
describe_cloudtrail_trail() {
    local trail_arn="$1"   # 対象証跡ARN
    local trail_name       # 見出し用の証跡名
    trail_name=$(echo "$trail_arn" | awk -F'trail/' '{print $2}')
    log "CloudTrail Trail: $trail_name"
    out "### CloudTrail Trail: \`$trail_name\`"
    out ""
    out_optional "Trail設定" aws_cmd cloudtrail get-trail --name "$trail_arn"
    out_optional "Trail Status" aws_cmd cloudtrail get-trail-status --name "$trail_arn"
    out_optional "Event Selectors" aws_cmd cloudtrail get-event-selectors --trail-name "$trail_arn"
}

#===============================================================================
# S3リソース describe関数
#===============================================================================

# S3バケットの設定値を取得（複数のAPIを呼び出し）
# 引数: $1=バケット名
describe_s3_bucket() {
    local bucket_name="$1"
    log "S3 Bucket: $bucket_name"
    out "### S3 Bucket: \`$bucket_name\`"
    out ""

    # 各設定をサブコマンドで取得（存在しない設定はスキップ）
    local subcmds=(
        "get-bucket-location"
        "get-bucket-versioning"
        "get-bucket-encryption"
        "get-bucket-policy"
        "get-bucket-acl"
        "get-bucket-tagging"
        "get-bucket-lifecycle-configuration"
        "get-public-access-block"
        "get-bucket-notification-configuration"
        "get-bucket-ownership-controls"
    )

    for subcmd in "${subcmds[@]}"; do
        local result
        # 一部のサブコマンドはバケットが該当設定を持たないとエラーになる
        if result=$(aws_cmd s3api "$subcmd" --bucket "$bucket_name" 2>/dev/null); then
            out "#### ${subcmd}"
            out ""
            out_json "$result"
        fi
    done
}

#===============================================================================
# Lambda関数 describe関数
#===============================================================================

# Lambda関数の設定値を取得
# 引数: $1=関数名
describe_lambda_function() {
    local func_name="$1"
    log "Lambda Function: $func_name"
    out "### Lambda Function: \`$func_name\`"
    out ""
    local result
    result=$(aws_cmd lambda get-function --function-name "$func_name")
    out_json "$result"

    # リソースベースポリシー（S3等からの呼び出し許可）。未設定なら注記のみ
    out_optional "Resource-based Policy" aws_cmd lambda get-policy --function-name "$func_name"
}

#===============================================================================
# RDS describe関数
#===============================================================================

# RDSインスタンスの設定値を取得
# 引数: $1=DBインスタンス識別子
describe_rds_instance() {
    local db_id="$1"
    log "RDS Instance: $db_id"
    out "### RDS Instance: \`$db_id\`"
    out ""
    local result
    result=$(aws_cmd rds describe-db-instances --db-instance-identifier "$db_id")
    out_json "$result"
}

# RDSクラスターの設定値を取得
# 引数: $1=DBクラスター識別子
describe_rds_cluster() {
    local cluster_id="$1"
    log "RDS Cluster: $cluster_id"
    out "### RDS Cluster: \`$cluster_id\`"
    out ""
    local result
    result=$(aws_cmd rds describe-db-clusters --db-cluster-identifier "$cluster_id")
    out_json "$result"
}

#===============================================================================
# DynamoDB describe関数
#===============================================================================

# DynamoDBテーブルの設定値を取得
# 引数: $1=テーブル名
describe_dynamodb_table() {
    local table_name="$1"
    log "DynamoDB Table: $table_name"
    out "### DynamoDB Table: \`$table_name\`"
    out ""
    local result
    result=$(aws_cmd dynamodb describe-table --table-name "$table_name")
    out_json "$result"
}

#===============================================================================
# ELB (ALB/NLB) describe関数
#===============================================================================

# ロードバランサーの設定値を取得
# 引数: $1=ロードバランサーARN
describe_elbv2() {
    local lb_arn="$1"
    log "ELBv2: $lb_arn"
    local lb_name
    lb_name=$(echo "$lb_arn" | grep -oP '(?<=loadbalancer/)[^/]+/[^/]+' || echo "$lb_arn")
    out "### Load Balancer: \`$lb_name\`"
    out ""

    local result
    result=$(aws_cmd elbv2 describe-load-balancers --load-balancer-arns "$lb_arn")
    out "#### Load Balancer設定"
    out ""
    out_json "$result"

    # リスナー
    local listeners
    if listeners=$(aws_cmd elbv2 describe-listeners --load-balancer-arn "$lb_arn" 2>/dev/null); then
        out "#### Listeners"
        out ""
        out_json "$listeners"
    fi

    # ターゲットグループ
    local tgs
    if tgs=$(aws_cmd elbv2 describe-target-groups --load-balancer-arn "$lb_arn" 2>/dev/null); then
        out "#### Target Groups"
        out ""
        out_json "$tgs"
    fi
}

#===============================================================================
# CloudFormation describe関数
#===============================================================================

# CloudFormationスタックの設定値を取得
# 引数: $1=スタック名またはID
describe_cloudformation_stack() {
    local stack_id="$1"
    log "CloudFormation Stack: $stack_id"
    out "### CloudFormation Stack"
    out ""
    local result
    result=$(aws_cmd cloudformation describe-stacks --stack-name "$stack_id")
    out_json "$result"

    # スタックリソース一覧
    local resources
    if resources=$(aws_cmd cloudformation list-stack-resources --stack-name "$stack_id" 2>/dev/null); then
        out "#### Stack Resources"
        out ""
        out_json "$resources"
    fi
}

#===============================================================================
# SNS describe関数
#===============================================================================

# SNSトピックの設定値を取得
# 引数: $1=トピックARN
describe_sns_topic() {
    local topic_arn="$1"
    log "SNS Topic: $topic_arn"
    local topic_name
    topic_name=$(echo "$topic_arn" | awk -F: '{print $NF}')
    out "### SNS Topic: \`$topic_name\`"
    out ""
    local result
    result=$(aws_cmd sns get-topic-attributes --topic-arn "$topic_arn")
    out_json "$result"
}

#===============================================================================
# SQS describe関数
#===============================================================================

# SQSキューの設定値を取得
# 引数: $1=キューARN
describe_sqs_queue() {
    local queue_arn="$1"
    log "SQS Queue: $queue_arn"
    local queue_name
    queue_name=$(echo "$queue_arn" | awk -F: '{print $NF}')
    out "### SQS Queue: \`$queue_name\`"
    out ""

    # ARNからURLを構築
    local account_id region
    account_id=$(echo "$queue_arn" | awk -F: '{print $5}')
    region=$(echo "$queue_arn" | awk -F: '{print $4}')
    local queue_url="https://sqs.${region}.amazonaws.com/${account_id}/${queue_name}"

    local result
    result=$(aws_cmd sqs get-queue-attributes --queue-url "$queue_url" --attribute-names All)
    out_json "$result"
}

#===============================================================================
# IAMリソース describe関数群（プレフィクスベース検索）
#===============================================================================

# IAMロールの設定値を取得（インラインポリシー・アタッチドポリシー含む）
# 引数: $1=ロール名
describe_iam_role() {
    local role_name="$1"
    log "IAM Role: $role_name"
    out "### IAM Role: \`$role_name\`"
    out ""

    # ロール本体（Trust Policy含む）
    local result
    result=$(aws_iam get-role --role-name "$role_name")
    out "#### Role設定"
    out ""
    out_json "$result"

    # インラインポリシー一覧と各ポリシーの内容
    local inline_policies
    inline_policies=$(aws_iam list-role-policies --role-name "$role_name" | jq -r '.PolicyNames[]')
    if [[ -n "$inline_policies" ]]; then
        out "#### Inline Policies"
        out ""
        while IFS= read -r policy_name; do
            local policy_doc
            policy_doc=$(aws_iam get-role-policy --role-name "$role_name" --policy-name "$policy_name")
            out "##### \`$policy_name\`"
            out ""
            out_json "$policy_doc"
        done <<< "$inline_policies"
    fi

    # アタッチドマネージドポリシー一覧
    local attached
    attached=$(aws_iam list-attached-role-policies --role-name "$role_name")
    local attached_count
    attached_count=$(echo "$attached" | jq '.AttachedPolicies | length')
    if [[ "$attached_count" -gt 0 ]]; then
        out "#### Attached Managed Policies"
        out ""
        out_json "$attached"
    fi
}

# IAMユーザーの設定値を取得
# 引数: $1=ユーザー名
describe_iam_user() {
    local user_name="$1"
    log "IAM User: $user_name"
    out "### IAM User: \`$user_name\`"
    out ""

    # ユーザー本体
    local result
    result=$(aws_iam get-user --user-name "$user_name")
    out "#### User設定"
    out ""
    out_json "$result"

    # インラインポリシー
    local inline_policies
    inline_policies=$(aws_iam list-user-policies --user-name "$user_name" | jq -r '.PolicyNames[]')
    if [[ -n "$inline_policies" ]]; then
        out "#### Inline Policies"
        out ""
        while IFS= read -r policy_name; do
            local policy_doc
            policy_doc=$(aws_iam get-user-policy --user-name "$user_name" --policy-name "$policy_name")
            out "##### \`$policy_name\`"
            out ""
            out_json "$policy_doc"
        done <<< "$inline_policies"
    fi

    # アタッチドマネージドポリシー
    local attached
    attached=$(aws_iam list-attached-user-policies --user-name "$user_name")
    local attached_count
    attached_count=$(echo "$attached" | jq '.AttachedPolicies | length')
    if [[ "$attached_count" -gt 0 ]]; then
        out "#### Attached Managed Policies"
        out ""
        out_json "$attached"
    fi

    # アクセスキー情報（キー値は出力されない、メタデータのみ）
    local access_keys
    access_keys=$(aws_iam list-access-keys --user-name "$user_name")
    local key_count
    key_count=$(echo "$access_keys" | jq '.AccessKeyMetadata | length')
    if [[ "$key_count" -gt 0 ]]; then
        out "#### Access Keys（メタデータのみ）"
        out ""
        out_json "$access_keys"
    fi

    # グループ
    local groups
    groups=$(aws_iam list-groups-for-user --user-name "$user_name")
    local group_count
    group_count=$(echo "$groups" | jq '.Groups | length')
    if [[ "$group_count" -gt 0 ]]; then
        out "#### Groups"
        out ""
        out_json "$groups"
    fi
}

# IAMカスタマーマネージドポリシーの設定値を取得
# 引数: $1=ポリシー名
describe_iam_policy() {
    local policy_name="$1"
    log "IAM Policy: $policy_name"
    out "### IAM Policy: \`$policy_name\`"
    out ""

    # ポリシーのARNを取得
    local policy_arn
    policy_arn=$(aws_iam list-policies --scope Local --output json \
        | jq -r --arg name "$policy_name" '.Policies[] | select(.PolicyName == $name) | .Arn')

    if [[ -z "$policy_arn" ]]; then
        out "> ポリシーが見つかりませんでした。"
        out ""
        return
    fi

    # ポリシー本体
    local result
    result=$(aws_iam get-policy --policy-arn "$policy_arn")
    out "#### Policy設定"
    out ""
    out_json "$result"

    # デフォルトバージョンのポリシードキュメント
    local default_version
    default_version=$(echo "$result" | jq -r '.Policy.DefaultVersionId')
    local policy_doc
    policy_doc=$(aws_iam get-policy-version --policy-arn "$policy_arn" --version-id "$default_version")
    out "#### Policy Document (${default_version})"
    out ""
    out_json "$policy_doc"
}

# IAM Instance Profileの設定値を取得（紐づくロール含む）
# 引数: $1=Instance Profile名
describe_iam_instance_profile() {
    local profile_name="$1"   # 対象Instance Profile名
    log "IAM InstanceProfile: $profile_name"
    out "### IAM Instance Profile: \`$profile_name\`"
    out ""
    local result
    result=$(aws_iam get-instance-profile --instance-profile-name "$profile_name")
    out_json "$result"
}

#===============================================================================
# 名前プレフィクス検索: タグ付け漏れに備え、名前がプレフィクスに一致する
# リソースのARNを列挙する（IAMはPhase 2で別途扱う）。
# 引数: $1=名前プレフィクス
# 出力: ARNを1行ずつ標準出力へ
#===============================================================================
collect_by_name_prefix() {
    local prefix="$1"                                       # 名前プレフィクス
    local arn_head="arn:aws:ec2:${REGION}:${ACTUAL_ACCOUNT_ID}"  # EC2 ARNの共通部分
    local spec cmd jq_expr res_type                         # EC2検索定義とその分解結果

    # EC2: Nameタグで検索。定義は「describeコマンド|IDを取り出すjq式|ARNのリソースタイプ」
    local ec2_specs=(
        "describe-vpcs|.Vpcs[].VpcId|vpc"
        "describe-subnets|.Subnets[].SubnetId|subnet"
        "describe-internet-gateways|.InternetGateways[].InternetGatewayId|internet-gateway"
        "describe-route-tables|.RouteTables[].RouteTableId|route-table"
        "describe-security-groups|.SecurityGroups[].GroupId|security-group"
        "describe-instances|.Reservations[].Instances[] | select(.State.Name != \"terminated\") | .InstanceId|instance"
        "describe-volumes|.Volumes[].VolumeId|volume"
    )
    for spec in "${ec2_specs[@]}"; do
        cmd="${spec%%|*}"
        res_type="${spec##*|}"
        jq_expr="${spec#*|}"
        jq_expr="${jq_expr%|*}"
        aws_cmd ec2 "$cmd" --filters "Name=tag:Name,Values=${prefix}*" \
            | jq -r "$jq_expr" \
            | sed "s|^|${arn_head}:${res_type}/|"
    done

    # S3（グローバルに一覧されるバケット名で判定）
    aws_cmd s3api list-buckets \
        | jq -r --arg p "$prefix" '.Buckets[] | select(.Name | startswith($p)) | "arn:aws:s3:::" + .Name'

    # Lambda
    aws_cmd lambda list-functions \
        | jq -r --arg p "$prefix" '.Functions[] | select(.FunctionName | startswith($p)) | .FunctionArn'

    # CloudWatch Logs（タグAPIと表記を揃えるため末尾 :* なしで組み立てる）
    aws_cmd logs describe-log-groups --log-group-name-prefix "$prefix" \
        | jq -r --arg h "arn:aws:logs:${REGION}:${ACTUAL_ACCOUNT_ID}:log-group:" '.logGroups[] | $h + .logGroupName'

    # CloudTrail
    aws_cmd cloudtrail describe-trails \
        | jq -r --arg p "$prefix" '.trailList[] | select(.Name | startswith($p)) | .TrailARN'

    # SNS（ARN末尾のトピック名で判定）
    aws_cmd sns list-topics \
        | jq -r --arg p "$prefix" '.Topics[].TopicArn | select(split(":")[-1] | startswith($p))'
}

# ARN一覧を正規化する（空行除去・ロググループARN末尾の :* 除去・重複除去）
# 入力: ARN一覧（stdin）
normalize_arns() {
    sed -e '/^$/d' -e 's/:\*$//' | sort -u
}

# 行数を数える（空文字列なら0）
# 引数: $1=改行区切りの文字列
count_lines() {
    if [[ -z "$1" ]]; then echo 0; else echo "$1" | wc -l; fi
}

#===============================================================================
# ARNパーサー: ARNからサービスとリソースタイプを抽出し、
# 対応するdescribe関数にディスパッチする。
#
# ARN形式: arn:aws:SERVICE:REGION:ACCOUNT:RESOURCE_TYPE/RESOURCE_ID
#          arn:aws:SERVICE:REGION:ACCOUNT:RESOURCE_TYPE:RESOURCE_ID
#          arn:aws:s3:::BUCKET_NAME
#===============================================================================
dispatch_describe() {
    local arn="$1"

    # ARNの各フィールドを分解
    local service resource_part
    service=$(echo "$arn" | awk -F: '{print $3}')
    # 6番目以降をすべて結合（:区切りのリソースIDに対応）
    resource_part=$(echo "$arn" | cut -d: -f6-)

    case "$service" in
        ec2)
            # resource_part: "vpc/vpc-xxx" or "subnet/subnet-xxx" etc.
            local resource_type resource_id
            resource_type=$(echo "$resource_part" | cut -d'/' -f1)
            resource_id=$(echo "$resource_part" | cut -d'/' -f2-)

            case "$resource_type" in
                vpc)                describe_ec2_vpc "$resource_id" ;;
                subnet)             describe_ec2_subnet "$resource_id" ;;
                internet-gateway)   describe_ec2_igw "$resource_id" ;;
                route-table)        describe_ec2_route_table "$resource_id" ;;
                security-group)      describe_ec2_security_group "$resource_id" ;;
                security-group-rule) log "SecurityGroupRule: $resource_id → 親SGのIpPermissionsに含まれるためスキップ" ;;
                instance)            describe_ec2_instance "$resource_id" ;;
                natgateway)          describe_ec2_natgateway "$resource_id" ;;
                elastic-ip)          describe_ec2_eip "$resource_id" ;;
                network-interface)   describe_ec2_network_interface "$resource_id" ;;
                network-acl)         describe_ec2_network_acl "$resource_id" ;;
                volume)              describe_ec2_volume "$resource_id" ;;
                *)                   log_skip "未対応EC2リソースタイプ: $resource_type ($arn)" ;;
            esac
            ;;
        s3)
            # S3 ARN: arn:aws:s3:::bucket-name
            local bucket_name
            bucket_name=$(echo "$arn" | awk -F::: '{print $2}')
            describe_s3_bucket "$bucket_name"
            ;;
        lambda)
            # lambda ARN: arn:aws:lambda:REGION:ACCOUNT:function:FUNC_NAME
            local func_name
            func_name=$(echo "$resource_part" | cut -d: -f2)
            describe_lambda_function "$func_name"
            ;;
        rds)
            case "$resource_part" in
                db:*)       describe_rds_instance "$(echo "$resource_part" | cut -d: -f2)" ;;
                cluster:*)  describe_rds_cluster "$(echo "$resource_part" | cut -d: -f2)" ;;
                *)          log_skip "未対応RDSリソースタイプ: $resource_part ($arn)" ;;
            esac
            ;;
        dynamodb)
            # arn:aws:dynamodb:REGION:ACCOUNT:table/TABLE_NAME
            local table_name
            table_name=$(echo "$resource_part" | cut -d'/' -f2)
            describe_dynamodb_table "$table_name"
            ;;
        elasticloadbalancing)
            describe_elbv2 "$arn"
            ;;
        cloudformation)
            local stack_id
            stack_id=$(echo "$resource_part" | cut -d'/' -f2)
            describe_cloudformation_stack "$stack_id"
            ;;
        sns)
            describe_sns_topic "$arn"
            ;;
        sqs)
            describe_sqs_queue "$arn"
            ;;
        logs)
            # logs ARN: arn:aws:logs:REGION:ACCOUNT:log-group:GROUP_NAME[:*]
            # ロググループ名に ":" は使えないため2番目のフィールドが名前
            describe_logs_group "$(echo "$resource_part" | cut -d: -f2)"
            ;;
        cloudtrail)
            # cloudtrail ARN: arn:aws:cloudtrail:REGION:ACCOUNT:trail/TRAIL_NAME
            describe_cloudtrail_trail "$arn"
            ;;
        *)
            log_skip "未対応サービス: $service ($arn)"
            ;;
    esac
}

#===============================================================================
# メイン処理
#===============================================================================

# 出力ファイル初期化
: > "$OUTPUT_FILE"

# ヘッダー出力
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S %Z')
out "# AWS Resource Configuration Report"
out ""
out "- **Tag**: \`${TAG_KEY}=${TAG_VALUE}\`"
out "- **Profile**: \`${PROFILE}\`"
out "- **Region**: \`${REGION}\`"
out "- **Generated**: ${TIMESTAMP}"
out ""

#--- Phase 1: タグベースリソース取得 ---
log "Phase 1: resourcegroupstaggingapi でタグ付きリソースを検索..."
out "## Tagged Resources (\`${TAG_KEY}=${TAG_VALUE}\`)"
out ""

TAGGED_ARNS=$(aws_cmd resourcegroupstaggingapi get-resources \
    --tag-filters "Key=${TAG_KEY},Values=${TAG_VALUE}" \
    | jq -r '.ResourceTagMappingList[].ResourceARN' | normalize_arns)

# 名前プレフィクス検索（-i 指定時のみ）
NAMED_ARNS=""       # 名前プレフィクスに一致したARN一覧
UNTAGGED_ARNS=""    # 名前は一致するがタグ検索で見つからなかったARN一覧（タグ付け漏れ候補）
if [[ -n "$IAM_PREFIX" ]]; then
    log "Phase 1b: 名前プレフィクス '${IAM_PREFIX}' でリソースを検索..."
    NAMED_ARNS=$(collect_by_name_prefix "$IAM_PREFIX" | normalize_arns)
    UNTAGGED_ARNS=$(comm -13 <(echo "$TAGGED_ARNS") <(echo "$NAMED_ARNS") | sed '/^$/d')
fi

# タグ検索と名前検索の和集合（重複除去済み）
ALL_ARNS=$(printf '%s\n%s\n' "$TAGGED_ARNS" "$NAMED_ARNS" | normalize_arns)

log "  タグ一致 $(count_lines "$TAGGED_ARNS") 件 / 名前一致 $(count_lines "$NAMED_ARNS") 件 / 合計 $(count_lines "$ALL_ARNS") 件"
out "- タグ一致: $(count_lines "$TAGGED_ARNS") 件"
[[ -n "$IAM_PREFIX" ]] && out "- 名前一致（prefix: \`${IAM_PREFIX}\`）: $(count_lines "$NAMED_ARNS") 件"
out "- 検出リソース数（重複除去後）: $(count_lines "$ALL_ARNS")"
out ""

# タグ付け漏れ候補を警告として列挙
if [[ -n "$UNTAGGED_ARNS" ]]; then
    log "  [WARN] タグ無しで名前一致: $(count_lines "$UNTAGGED_ARNS") 件"
    out "> **WARN**: 名前は一致するがタグ \`${TAG_KEY}=${TAG_VALUE}\` が無いリソース"
    out ""
    while IFS= read -r arn; do
        out "- \`$(echo "$arn" | mask_account_id)\`"
    done <<< "$UNTAGGED_ARNS"
    out ""
fi

if [[ -z "$ALL_ARNS" ]]; then
    out "> 該当するリソースは見つかりませんでした。"
    out ""
else
    # 各ARNに対してdescribeを実行
    while IFS= read -r arn; do
        [[ -z "$arn" ]] && continue
        dispatch_describe "$arn"
    done <<< "$ALL_ARNS"
fi

#--- Phase 2: IAMリソース（プレフィクスベース） ---
if [[ -n "$IAM_PREFIX" ]]; then
    log "Phase 2: IAMリソースをプレフィクス '${IAM_PREFIX}' で検索..."
    out "## IAM Resources (prefix: \`${IAM_PREFIX}\`)"
    out ""

    # IAMロール
    IAM_ROLES=$(aws_iam list-roles | jq -r --arg prefix "$IAM_PREFIX" \
        '.Roles[] | select(.RoleName | startswith($prefix)) | .RoleName')
    if [[ -n "$IAM_ROLES" ]]; then
        while IFS= read -r role_name; do
            [[ -z "$role_name" ]] && continue
            describe_iam_role "$role_name"
        done <<< "$IAM_ROLES"
    else
        out "> プレフィクス \`${IAM_PREFIX}\` に一致するIAMロールはありませんでした。"
        out ""
    fi

    # IAMユーザー
    IAM_USERS=$(aws_iam list-users | jq -r --arg prefix "$IAM_PREFIX" \
        '.Users[] | select(.UserName | startswith($prefix)) | .UserName')
    if [[ -n "$IAM_USERS" ]]; then
        while IFS= read -r user_name; do
            [[ -z "$user_name" ]] && continue
            describe_iam_user "$user_name"
        done <<< "$IAM_USERS"
    else
        out "> プレフィクス \`${IAM_PREFIX}\` に一致するIAMユーザーはありませんでした。"
        out ""
    fi

    # IAMポリシー（カスタマーマネージド）
    IAM_POLICIES=$(aws_iam list-policies --scope Local | jq -r --arg prefix "$IAM_PREFIX" \
        '.Policies[] | select(.PolicyName | startswith($prefix)) | .PolicyName')
    if [[ -n "$IAM_POLICIES" ]]; then
        while IFS= read -r policy_name; do
            [[ -z "$policy_name" ]] && continue
            describe_iam_policy "$policy_name"
        done <<< "$IAM_POLICIES"
    else
        out "> プレフィクス \`${IAM_PREFIX}\` に一致するIAMポリシーはありませんでした。"
        out ""
    fi

    # IAM Instance Profile
    IAM_PROFILES=$(aws_iam list-instance-profiles | jq -r --arg prefix "$IAM_PREFIX" \
        '.InstanceProfiles[] | select(.InstanceProfileName | startswith($prefix)) | .InstanceProfileName')
    if [[ -n "$IAM_PROFILES" ]]; then
        while IFS= read -r profile_name; do
            [[ -z "$profile_name" ]] && continue
            describe_iam_instance_profile "$profile_name"
        done <<< "$IAM_PROFILES"
    else
        out "> プレフィクス \`${IAM_PREFIX}\` に一致するIAM Instance Profileはありませんでした。"
        out ""
    fi
fi

#--- Phase 3: SES identity（参考: リージョン内の全件） ---
# identity はメールアドレス/ドメイン名のため、プロジェクトとの対応は判別しない
log "Phase 3: SES identity を取得..."
out "## SES Identities (参考: \`${REGION}\` の全 identity)"
out ""
SES_IDS=()   # SES identity の一覧（メールアドレス/ドメイン）
if ses_list=$(aws_cmd ses list-identities 2>&1); then
    mapfile -t SES_IDS < <(echo "$ses_list" | jq -r '.Identities[]')
    if [[ ${#SES_IDS[@]} -eq 0 ]]; then
        out "> SES identity はありませんでした。"
        out ""
    else
        out_optional "Verification Attributes" \
            aws_cmd ses get-identity-verification-attributes --identities "${SES_IDS[@]}"
    fi
else
    out "> 取得なし: $(echo "$ses_list" | tail -n 1 | mask_account_id)"
    out ""
fi

#--- 完了 ---
out "---"
out ""
out "*Report generated by aws-describe-tagged-resources.sh*"

log "完了: ${OUTPUT_FILE}"
log "アカウントID ${ACTUAL_ACCOUNT_ID} は '${ACCOUNT_ID_MASK}' にマスクされています。"
