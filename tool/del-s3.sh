#!/usr/bin/env bash
#------------------------------------------------------------------------------
# del-s3.sh
# Created     : 2026-09-22 10:25:18
# Last updated: 2026-09-22 13:56:17
# Author      : tsystem
# 概要        : S3 バケット内のオブジェクトをすべて削除する（取り消せない）。
#   使い方: ../tool/del-s3.sh [バケット]   （省略時 ts-030-bkt-in。ASSUME_YES=1 で確認省略）
#   EC2 が動作中（入力のダウンロード中の可能性）は中止する
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
readonly BUCKET_IN=ts-030-bkt-in                       # 入力バケット
readonly BUCKET_OUT=ts-030-bkt-out                     # 出力バケット
readonly EC2_NAME=${EC2_NAME:-ts-030-ec2-010}          # Lambda が起動する EC2 の Name タグ（run.conf の ec2_instance_name_tag。環境変数で上書き可）

#------------------------------------------------------------------------------
# 関数
#------------------------------------------------------------------------------
# main : バケット内のオブジェクトをすべて削除する（バージョニング無しのため取り消せない）。
#        EC2（ts-030-ec2-010）が動作中は、入力のダウンロード中の可能性があるため中止する。
#   引数 : $1 … 対象バケット（省略時 ts-030-bkt-in。ts-030-bkt-in / ts-030-bkt-out のみ）
#          環境変数 ASSUME_YES=1 … 削除前の確認を省略する
#   戻り値: 0=全件削除（空バケット含む） / ERR=前提不備・EC2 動作中・中止・失敗が1件以上
main() {
  # NOTE: コマンド実行後は必ず rc=$? で戻り値を取得し、エラー制御を行うこと。
  #       set -e は使用しない。戻り値は手動でキャプチャして制御する。
  local rc=0                          # 直近コマンドの戻り値
  local bucket="${1:-${BUCKET_IN}}"   # 対象バケット
  local arn="" running="" objects=""  # 認証確認の ARN／動作中の EC2 件数／オブジェクト一覧（JSON）
  local count=0 bytes=0 ans=""        # 対象件数／合計バイト数／確認への回答
  local key=""                        # オブジェクトキー
  local ok=0 ng=0                     # 削除成功件数／失敗件数

  #--- 前提確認（対象バケット・認証） ---
  [[ "${bucket}" == "${BUCKET_IN}" || "${bucket}" == "${BUCKET_OUT}" ]] \
    || { log "ERROR: bucket must be ${BUCKET_IN} or ${BUCKET_OUT}: ${bucket}"; return "${ERR}"; }
  arn=$(aws sts get-caller-identity --profile "${PROFILE_S3}" --query Arn --output text); rc=$?
  [[ ${rc} -eq 0 ]] || { log "ERROR: authentication failed (profile ${PROFILE_S3})"; return "${ERR}"; }
  log "identity: ${arn}"

  #--- EC2 が動作中なら中止（確認できない場合も安全側で中止） ---
  running=$(aws ec2 describe-instances --profile "${PROFILE_RO}" --region "${REGION}" \
    --filters "Name=tag:Name,Values=${EC2_NAME}" "Name=instance-state-name,Values=pending,running,stopping,shutting-down" \
    --query 'length(Reservations[].Instances[])' --output text); rc=$?
  [[ ${rc} -eq 0 ]] || { log "ERROR: cannot check EC2 state (profile ${PROFILE_RO}) rc=${rc}"; return "${ERR}"; }
  [[ "${running}" == "0" ]] || { log "ERROR: ${EC2_NAME} is still active (${running}). wait until it terminates"; return "${ERR}"; }

  #--- オブジェクト一覧と件数・合計サイズ（空バケットは正常終了） ---
  objects=$(aws s3api list-objects-v2 --profile "${PROFILE_S3}" --bucket "${bucket}" \
    --query 'Contents[].{Key: Key, Size: Size}' --output json); rc=$?
  [[ ${rc} -eq 0 ]] || { log "ERROR: list failed: s3://${bucket} rc=${rc}"; return "${ERR}"; }
  count=$(jq 'length // 0' <<< "${objects}")
  if [[ "${count}" == "0" ]]; then
    log "s3://${bucket} is empty. nothing to do"
    return 0
  fi
  bytes=$(jq '[.[].Size] | add' <<< "${objects}")
  jq -r '.[] | "  \(.Key)\t\(.Size)"' <<< "${objects}"
  log "target: s3://${bucket} ${count} objects, ${bytes} bytes"

  #--- 確認（ASSUME_YES=1 で省略。端末が無ければ中止） ---
  if [[ "${ASSUME_YES:-0}" != "1" ]]; then
    { : < /dev/tty; } 2> /dev/null || { log "ERROR: no terminal for confirmation. set ASSUME_YES=1 to skip"; return "${ERR}"; }
    read -r -p "s3://${bucket} の ${count} 件を削除します（取り消せません）。続行しますか [y/N]: " ans < /dev/tty
    [[ "${ans}" == "y" || "${ans}" == "Y" ]] || { log "canceled by user"; return "${ERR}"; }
  fi

  #--- 1件ずつ削除 ---
  while IFS= read -r key; do
    aws s3 rm "s3://${bucket}/${key}" --profile "${PROFILE_S3}" --only-show-errors; rc=$?
    if [[ ${rc} -eq 0 ]]; then log "deleted: s3://${bucket}/${key}"; ok=$((ok+1))
    else log "NG: delete failed: s3://${bucket}/${key} rc=${rc}"; ng=$((ng+1)); fi
  done < <(jq -r '.[].Key' <<< "${objects}")

  log "result: total ${count}, deleted ${ok}, ng ${ng}"
  [[ ${ng} -eq 0 ]] || return "${ERR}"
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
