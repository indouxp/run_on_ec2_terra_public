#!/usr/bin/env bash
################################################################################
# ts-030 の IAM ロール（全ロールの本体・管理ポリシー・インラインポリシー）と、
# ネットワーク（IGW / ルートテーブル / VPC / サブネット）の設定を JSON / YAML に出力する。
# 参照のみ（プロファイル ts-usr-readonly）。出力ファイル info-ts-030-*.json / .yaml は .gitignore 済み。
#
# Last updated: 2026-09-22 13:57:10
################################################################################

# ロール一覧（名前が ts-030- で始まるもの。build / lambda-010 / ec2-010 / operate など複数ある）
ROLE_NAMES=$(AWS_PROFILE=ts-usr-readonly \
             aws iam list-roles \
               --output json \
             | jq -r '.Roles[] | select(.RoleName | startswith("ts-030-")) | .RoleName')

OUTPUT_JSON="info-ts-030-role.json"    # JSON出力先ファイル（ロールごとのオブジェクトの配列）
OUTPUT_YAML="info-ts-030-role.yaml"   # YAML出力先ファイル

# ロールごとに、本体・アタッチ済み管理ポリシー・インラインポリシー名と本文を1オブジェクトにまとめる
# （以前は全ロール名を1つの --role-name に渡しており、ロールが2本以上あると失敗していた）
for ROLE in ${ROLE_NAMES}; do
  # インラインポリシーの本文を {"InlinePolicies": {ポリシー名: 本文}} の形にする
  INLINE_JSON=$(for POLICY_NAME in $(AWS_PROFILE=ts-usr-readonly aws iam list-role-policies \
                                       --role-name "${ROLE}" --query 'PolicyNames[]' --output text); do
                  AWS_PROFILE=ts-usr-readonly aws iam get-role-policy \
                    --role-name "${ROLE}" --policy-name "${POLICY_NAME}" --output json
                done | jq -s '{InlinePolicies: (map({(.PolicyName): .PolicyDocument}) | add // {})}')
  jq -s 'add' \
    <(AWS_PROFILE=ts-usr-readonly aws iam get-role --role-name "${ROLE}" --output json) \
    <(AWS_PROFILE=ts-usr-readonly aws iam list-attached-role-policies --role-name "${ROLE}" --output json) \
    <(echo "${INLINE_JSON}")
done | jq -s '.' > "${OUTPUT_JSON}"
echo "出力完了: ${OUTPUT_JSON}（ロール $(jq 'length' "${OUTPUT_JSON}") 件）"

# JSONをYAMLに変換
python3 -c "
import json, yaml
with open('${OUTPUT_JSON}') as f:
    data = json.load(f)
with open('${OUTPUT_YAML}', 'w') as f:
    yaml.dump(data, f, allow_unicode=True, default_flow_style=False, sort_keys=False)
print('変換完了: ${OUTPUT_YAML}')
"

# Project=ts-030のもの
ARNS=$(AWS_PROFILE=ts-usr-readonly \
         aws resourcegroupstaggingapi get-resources \
           --region ap-northeast-1 \
           --tag-filters "Key=Project,Values=ts-030" \
           --query "ResourceTagMappingList[].ResourceARN" \
           --output json)
# 各リソースID
IGW_ID=$(echo "${ARNS}"    | jq -r '.[] | select(contains("internet-gateway")) | split("/")[-1]')
RTB_ID=$(echo "${ARNS}"    | jq -r '.[] | select(contains("route-table"))      | split("/")[-1]')
VPC_ID=$(echo "${ARNS}"    | jq -r '.[] | select(contains(":vpc/"))            | split("/")[-1]')
SUBNET_ID=$(echo "${ARNS}" | jq -r '.[] | select(contains("subnet"))           | split("/")[-1]')

# 出力先ファイル
OUTPUT_JSON="info-ts-030-detail.json"
OUTPUT_YAML="info-ts-030-detail.yaml"

# AWS共通設定
AWS_PROFILE_NAME="ts-usr-readonly"
AWS_REGION="ap-northeast-1"

#IGW_ID="igw-0123456789abcdef0"
#RTB_ID="rtb-0123456789abcdef0"
#VPC_ID="vpc-0123456789abcdef0"
#SUBNET_ID="subnet-0123456789abcdef0"

# 各リソースの全属性をjsonで取得し、プロセス置換で渡してjqで1ファイルに結合
jq -s 'add' \
  <(AWS_PROFILE=${AWS_PROFILE_NAME} aws ec2 describe-internet-gateways \
      --region ${AWS_REGION} \
      --internet-gateway-ids ${IGW_ID} \
      --output json) \
  <(AWS_PROFILE=${AWS_PROFILE_NAME} aws ec2 describe-route-tables \
      --region ${AWS_REGION} \
      --route-table-ids ${RTB_ID} \
      --output json) \
  <(AWS_PROFILE=${AWS_PROFILE_NAME} aws ec2 describe-vpcs \
      --region ${AWS_REGION} \
      --vpc-ids ${VPC_ID} \
      --output json) \
  <(AWS_PROFILE=${AWS_PROFILE_NAME} aws ec2 describe-subnets \
      --region ${AWS_REGION} \
      --subnet-ids ${SUBNET_ID} \
      --output json) \
> ${OUTPUT_JSON}

echo "出力完了: ${OUTPUT_JSON}"

python3 -c "
import json, yaml, sys
output_json = sys.argv[1]
output_yaml = sys.argv[2]
with open(output_json) as f:
    data = json.load(f)
with open(output_yaml, 'w') as f:
    yaml.dump(data, f, allow_unicode=True, default_flow_style=False, sort_keys=False)
print('変換完了: ' + output_yaml)
" "${OUTPUT_JSON}" "${OUTPUT_YAML}"
