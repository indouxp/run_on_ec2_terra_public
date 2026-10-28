#!/usr/bin/env bash
#------------------------------------------------------------------------------
# get-now.sh
# Created     : 2026-09-22 10:25:18
# Last updated: 2026-09-22 11:05:36
# Author      : tsystem
# 概要        : システムの現在の状態（認証・EC2・S3 in/out・Lambda と EC2 のログ末尾）を1つのログに出力する。
#   使い方: ../tool/get-now.sh [行数]   （ログ末尾の行数。省略時 20）。参照のみで何も変更しない
#   雛形: skl078.sh（exec でログを端末と LOG_DIR（既定 /tmp）の両方へ出力。割り込み未処理）
#------------------------------------------------------------------------------
set -uo pipefail

readonly ERR=${ERR:-1}                              # エラー終了コード（呼び出し側で使用する想定の定数）
readonly WARN=${WARN:-255}                          # 警告終了コード（呼び出し側で使用する想定の定数）
readonly SCRIPT_NAME=${0##*/}                       # スクリプト名（パス除去したファイル名）
readonly SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)  # スクリプト設置ディレクトリ（絶対パス）
readonly LOG_DIR=${LOG_DIR:-/tmp}                   # ログ出力先。LOG_DIR環境変数が未定義時は /tmp
# ホスト名。$HOSTNAME 未定義環境に備え hostname コマンドへフォールバック
readonly HOSTNAME_S=${HOSTNAME:-$(hostname -s 2>/dev/null || echo unknown)}
readonly LOG_NAME=${SCRIPT_NAME}.$(date '+%Y%m%d_%H%M%S').${HOSTNAME_S}.$$.log  # ログファイル名（日時+ホスト+PIDで衝突回避）
readonly LOG_PATH="${LOG_DIR}/${LOG_NAME}"          # ログファイルの絶対パス
readonly PROFILE_S3=ts-030-role-operate                # S3 操作のプロファイル（ts-030-usr-operate → ts-030-role-operate を AssumeRole）
readonly PROFILE_RO=ts-usr-readonly                    # EC2・CloudWatch Logs 参照のプロファイル（in/out は Deny フェンスで参照不可）
readonly REGION=ap-northeast-1                         # リージョン
readonly PRJ=ts-030                                    # Project タグの値
readonly BUCKET_IN=ts-030-bkt-in                       # 入力バケット
readonly BUCKET_OUT=ts-030-bkt-out                     # 出力バケット
readonly LOG_GROUP_LAMBDA=/aws/lambda/ts-030-lmd-010   # Lambda のロググループ（Lambda 既定の出力先）
readonly LOG_GROUP_EC2=ts-030-log-ec2-010              # EC2（cloud-init-output.log）のロググループ

#------------------------------------------------------------------------------
# 関数
#------------------------------------------------------------------------------
# main : システムの現在の状態を1つのログにまとめて出力する（参照のみで何も変更しない）。
#        ① 認証 ② EC2 ③ S3 in/out ④ Lambda ログ末尾 ⑤ EC2 ログ末尾
#   引数 : $1 … ログ末尾の表示行数（省略時 20）
#   戻り値: 0=全項目取得 / ERR=取得できなかった項目が1つ以上（他の項目は出力を続ける）
main() {
  # NOTE: コマンド実行後は必ず rc=$? で戻り値を取得し、エラー制御を行うこと。
  #       set -e は使用しない。戻り値は手動でキャプチャして制御する。
  local rc=0                   # 直近コマンドの戻り値
  local lines="${1:-20}"       # ログ末尾の表示行数
  local failed=0               # 取得できなかった項目の数
  local profile="" bucket=""   # ループ中のプロファイル／バケット
  local out=""                 # コマンド出力の一時保持
  local group="" stream=""     # ロググループ／最新ログストリーム
  local log_groups=("${LOG_GROUP_LAMBDA}" "${LOG_GROUP_EC2}")  # 末尾を表示するロググループ

  [[ "${lines}" =~ ^[0-9]+$ ]] || { log "ERROR: lines must be a number: ${lines}"; return "${ERR}"; }

  #--- ① 認証（S3 用・参照用の各プロファイル） ---
  log "===== [1] identity ====="
  for profile in "${PROFILE_S3}" "${PROFILE_RO}"; do
    out=$(aws sts get-caller-identity --profile "${profile}" --query Arn --output text 2>&1); rc=$?
    if [[ ${rc} -eq 0 ]]; then echo "  ${profile}: ${out}"; else echo "  ${profile}: NG ${out}"; failed=$((failed+1)); fi
  done

  #--- ② EC2（Project=ts-030。terminated もしばらく表示される） ---
  log "===== [2] EC2 (tag Project=${PRJ}) ====="
  out=$(aws ec2 describe-instances --profile "${PROFILE_RO}" --region "${REGION}" \
    --filters "Name=tag:Project,Values=${PRJ}" --output json 2>&1); rc=$?
  if [[ ${rc} -eq 0 ]]; then
    jq -r '[.Reservations[].Instances[]] | if length == 0 then "  (none)" else .[] |
      "  \(.InstanceId)  \(.State.Name)  \(.InstanceType)  launch=\(.LaunchTime)  reason=\(.StateTransitionReason // "-")" end' <<< "${out}"
  else
    echo "  NG ${out}"; failed=$((failed+1))
  fi

  #--- ③ S3 in / out（件数・合計サイズ・一覧） ---
  for bucket in "${BUCKET_IN}" "${BUCKET_OUT}"; do
    log "===== [3] s3://${bucket} ====="
    out=$(aws s3api list-objects-v2 --profile "${PROFILE_S3}" --bucket "${bucket}" \
      --query 'Contents[].{Key: Key, Size: Size, LastModified: LastModified}' --output json 2>&1); rc=$?
    if [[ ${rc} -eq 0 ]]; then
      jq -r 'if (. // []) | length == 0 then "  (empty)" else
        "  objects=\(length) total_bytes=\([.[].Size] | add)", (.[] | "  \(.LastModified)  \(.Size)\t\(.Key)") end' <<< "${out}"
    else
      echo "  NG ${out}"; failed=$((failed+1))
    fi
  done

  #--- ④⑤ ログ末尾（各ロググループの最新ストリームの末尾 N 行） ---
  for group in "${log_groups[@]}"; do
    log "===== [4/5] ${group} (last ${lines} events) ====="
    stream=$(aws logs describe-log-streams --profile "${PROFILE_RO}" --region "${REGION}" \
      --log-group-name "${group}" --order-by LastEventTime --descending --limit 1 \
      --query 'logStreams[0].logStreamName' --output text 2>&1); rc=$?
    if [[ ${rc} -ne 0 ]]; then echo "  NG ${stream}"; failed=$((failed+1)); continue; fi
    if [[ -z "${stream}" || "${stream}" == "None" ]]; then echo "  (no stream)"; continue; fi
    echo "  stream: ${stream}"
    out=$(aws logs get-log-events --profile "${PROFILE_RO}" --region "${REGION}" \
      --log-group-name "${group}" --log-stream-name "${stream}" --limit "${lines}" --output json 2>&1); rc=$?
    if [[ ${rc} -eq 0 ]]; then
      jq -r '.events[] | "  \(.timestamp / 1000 | floor | strflocaltime("%Y-%m-%d %H:%M:%S"))  \(.message | rtrimstr("\n"))"' <<< "${out}"
    else
      echo "  NG ${out}"; failed=$((failed+1))
    fi
  done

  log "items failed: ${failed}"
  [[ ${failed} -eq 0 ]] || return "${ERR}"
  return 0
}

#------------------------------------------------------------------------------
# log : 標準的な書式でログ1行を出力する。
#   引数 : $1 … 出力するメッセージ文字列
#   戻り値: なし
log() {
  local msg="$1"    # 出力メッセージ
  echo "$(date '+%Y-%m-%d %H:%M:%S') ${HOSTNAME_S} $$ ${SCRIPT_NAME}: ${msg}"
}

#------------------------------------------------------------------------------
# cleanup_old_logs : LOG_DIR 直下の当スクリプト・当ホスト由来の古いログを削除する。
#   引数 : なし
#   戻り値: find の終了コード
cleanup_old_logs() {
  # -maxdepth 1 : LOG_DIR 直下のみ（再帰させない）
  # -type f     : 通常ファイルのみ（ディレクトリ誤削除の防止）
  # -mtime +10  : 更新から10日より前のものを対象
  find "${LOG_DIR}" -maxdepth 1 -type f \
       -name "${SCRIPT_NAME}.*.${HOSTNAME_S}.*.log" \
       -mtime +10 -delete
}

#------------------------------------------------------------------------------
# 主処理
#------------------------------------------------------------------------------
exec > >(tee "$LOG_PATH") 2>&1   # 以降の全出力（stdout/stderr）を端末とログへ二重化
readonly TEE_PID=$!               # tee の PID。終了前にフラッシュ完了を待つために保持

log "START"
main "$@"
RC=$?                             # main の戻り値を退避（以降の処理で $? が上書きされる前に確保）
log "END RC=${RC}"

#------------------------------------------------------------------------------
# 後処理：古いログ削除（失敗時は WARN ログを残し、RC を WARN にする）
if ! cleanup_old_logs
then
  log "WARN: old log cleanup failed"
  RC="${WARN}"
fi

#------------------------------------------------------------------------------
# tee のフラッシュ待ち：自身のstdout/stderrを閉じてteeにEOFを送り、完了を待つ
exec 1>&- 2>&-
wait "${TEE_PID}" 2>/dev/null

exit ${RC}
