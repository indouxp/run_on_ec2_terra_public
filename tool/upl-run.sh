#!/usr/bin/env bash
#------------------------------------------------------------------------------
# upl-run.sh
# Created     : 2026-09-22 10:25:18
# Last updated: 2026-09-22 13:56:17
# Author      : tsystem
# 概要        : S3 入力バケットへ入力ファイル・実行シェル・定義ファイルをアップロードし、EC2 のバッチ処理を起動する。
#   使い方: ../tool/upl-run.sh [定義ファイル]   （work/ で実行。省略時 ./run.conf。ASSUME_YES=1 で確認省略）
#   注意: 定義ファイル（.conf）をアップロードした時点で EC2 が起動し課金が始まる
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
readonly BUCKET_IN=ts-030-bkt-in                       # 入力バケット
readonly PROFILE_RO=ts-usr-readonly                    # EC2 の動作確認に使う参照用プロファイル
readonly REGION=ap-northeast-1                         # リージョン
# Lambda（lambda_function.py の validate_config）と同じ必須キー
readonly REQUIRED_KEYS=(exec log result mail sms ec2_role_name subnet_name sg_name ec2_instance_name_tag output_bucket ses_from_email prj_prefix)

#------------------------------------------------------------------------------
# 関数
#------------------------------------------------------------------------------
# main : 入力ファイル → 実行シェル → 定義ファイルの順に S3 入力バケットへアップロードする。
#        定義ファイル（.conf）のアップロードで Lambda が EC2 を起動する（課金開始）。
#        アップロードするファイルをすべて先に確認し、1つでも無ければ何も送らずに終わる。
#   引数 : $1 … 定義ファイル（省略時 ./run.conf）
#          環境変数 ASSUME_YES=1 … 起動前の確認を省略する
#   戻り値: 0=成功 / ERR=前提不備・ファイル欠落・中止・アップロード失敗
main() {
  # NOTE: コマンド実行後は必ず rc=$? で戻り値を取得し、エラー制御を行うこと。
  #       set -e は使用しない。戻り値は手動でキャプチャして制御する。
  local rc=0                   # 直近コマンドの戻り値
  local conf="${1:-./run.conf}" # 定義ファイル
  local exec_args=()           # exec を空白で分割した配列（先頭=実行シェル、以降=入力ファイル）
  local exec_script=""         # 実行シェルのローカルパス（カレント → スクリプト設置ディレクトリの順に探す）
  local uploads=()             # アップロードするファイル（入力 → 実行シェル → 定義ファイルの順）
  local matched=()             # パターンに一致したローカルファイル
  local pattern="" file=""     # 入力ファイルのパターン／アップロード対象ファイル
  local itype="" ans=""        # 起動するインスタンスタイプ／確認への回答
  local arn=""                 # 認証確認で得たプリンシパル ARN
  local missing=""             # run.conf に無い必須キー
  local ec2_name="" running="" # 確認する EC2 の Name タグ／動作中の件数

  #--- 前提確認（jq・定義ファイル・認証） ---
  command -v jq > /dev/null || { log "ERROR: jq is not installed"; return "${ERR}"; }
  [[ -f "${conf}" ]] || { log "ERROR: config not found: ${conf}"; return "${ERR}"; }
  [[ "${conf}" == *.conf ]] || { log "ERROR: config must end with .conf (Lambda trigger suffix): ${conf}"; return "${ERR}"; }
  jq empty "${conf}"; rc=$?
  [[ ${rc} -eq 0 ]] || { log "ERROR: invalid JSON: ${conf}"; return "${ERR}"; }
  arn=$(aws sts get-caller-identity --profile "${PROFILE_S3}" --query Arn --output text); rc=$?
  [[ ${rc} -eq 0 ]] || { log "ERROR: authentication failed (profile ${PROFILE_S3})"; return "${ERR}"; }
  log "identity: ${arn}"

  #--- run.conf の内容確認（Lambda の検証と同じ条件。ここで弾けば EC2 を起動せずに済む） ---
  # --args 以降は文字列引数として扱われるため、run.conf は標準入力から渡す
  missing=$(jq -r --args '[$ARGS.positional[] as $k | select(has($k) | not) | $k] | join(" ")' "${REQUIRED_KEYS[@]}" < "${conf}")
  [[ -z "${missing}" ]] || { log "ERROR: missing required keys in ${conf}: ${missing}"; return "${ERR}"; }
  jq -e '(.mail | test("^.+@.+\\..+$")) and (.ses_from_email | test("^.+@.+\\..+$"))' "${conf}" > /dev/null \
    || { log "ERROR: invalid email format (mail / ses_from_email) in ${conf}"; return "${ERR}"; }
  jq -e '(.sms | type == "string") and (.sms | test("^\\+81[0-9]+$"))' "${conf}" > /dev/null \
    || { log "ERROR: sms must be a string like +81XXXXXXXXXX in ${conf}"; return "${ERR}"; }

  #--- 同じ Name タグの EC2 が動作中なら投入しない（Lambda もエラーにするが、先に止める） ---
  ec2_name=$(jq -r '.ec2_instance_name_tag' "${conf}")
  running=$(aws ec2 describe-instances --profile "${PROFILE_RO}" --region "${REGION}" \
    --filters "Name=tag:Name,Values=${ec2_name}" "Name=instance-state-name,Values=pending,running,stopping,shutting-down" \
    --query 'length(Reservations[].Instances[])' --output text); rc=$?
  [[ ${rc} -eq 0 ]] || { log "ERROR: cannot check EC2 state (profile ${PROFILE_RO}) rc=${rc}"; return "${ERR}"; }
  [[ "${running}" == "0" ]] || { log "ERROR: ${ec2_name} is still active (${running}). wait until it terminates"; return "${ERR}"; }

  #--- アップロード対象の組み立てと存在確認 ---
  read -r -a exec_args <<< "$(jq -r '.exec // empty' "${conf}")"
  [[ ${#exec_args[@]} -ge 1 ]] || { log "ERROR: exec is empty in ${conf}"; return "${ERR}"; }
  for pattern in "${exec_args[@]:1}"; do
    mapfile -t matched < <(compgen -G "${pattern}")
    [[ ${#matched[@]} -gt 0 ]] || { log "ERROR: no local file matches: ${pattern}"; return "${ERR}"; }
    uploads+=("${matched[@]}")
  done
  if [[ -f "${exec_args[0]}" ]]; then
    exec_script="${exec_args[0]}"
  elif [[ -f "${SCRIPT_DIR}/${exec_args[0]}" ]]; then
    exec_script="${SCRIPT_DIR}/${exec_args[0]}"
  else
    log "ERROR: exec script not found in . or ${SCRIPT_DIR}: ${exec_args[0]}"; return "${ERR}"
  fi
  uploads+=("${exec_script}" "${conf}")   # 定義ファイル（Lambda のトリガー）を必ず最後にする
  for file in "${uploads[@]}"; do
    [[ -f "${file}" ]] || { log "ERROR: file not found: ${file}"; return "${ERR}"; }
  done

  #--- 起動内容の表示と確認（ASSUME_YES=1 で省略。端末が無ければ中止） ---
  itype=$(jq -r '.instance_type // "c6i.4xlarge (Lambda default)"' "${conf}")
  log "config: ${conf} / instance_type: ${itype} / exec: ${exec_args[*]}"
  if [[ "${ASSUME_YES:-0}" != "1" ]]; then
    { : < /dev/tty; } 2> /dev/null || { log "ERROR: no terminal for confirmation. set ASSUME_YES=1 to skip"; return "${ERR}"; }
    read -r -p "定義ファイルのアップロードで EC2（${itype}）が起動します。続行しますか [y/N]: " ans < /dev/tty
    [[ "${ans}" == "y" || "${ans}" == "Y" ]] || { log "canceled by user"; return "${ERR}"; }
  fi

  #--- アップロード（入力 → 実行シェル → 定義ファイル） ---
  for file in "${uploads[@]}"; do
    log "upload: ${file} ($(du -h "${file}" | cut -f1))"
    aws s3 cp "${file}" "s3://${BUCKET_IN}/" --profile "${PROFILE_S3}" --only-show-errors; rc=$?
    [[ ${rc} -eq 0 ]] || { log "ERROR: upload failed: ${file} rc=${rc}"; return "${ERR}"; }
  done
  log "upload complete. Lambda should now launch the EC2 instance."
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
