#!/usr/bin/env bash
#------------------------------------------------------------------------------
# run.sh
# Created     : 2026-09-22 10:25:18
# Last updated: 2026-09-22 13:51:22
# Author      : tsystem
# 概要        : EC2 上で入力の tar.gz を展開し、動画（.MOV/.mov）を ffmpeg で mp4 に変換する。
#   user_data（infra/lambda/user_data_template.sh）が ec2-user で実行する。
#   使い方: ./run.sh 入力ファイル.tar.gz ...   （upl-run.sh で S3 に置き、run.conf の exec で指定）
#   出力: 変換した *.mp4 と simple-act.log（ホーム）。標準出力は user_data が run.log として out へ送る
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
ACT_PID=""                                              # アクティビティ取得（バックグラウンド）の PID。trap で参照するためグローバル

#------------------------------------------------------------------------------
# 関数
#------------------------------------------------------------------------------
# main : EC2 上で入力ファイル（tar.gz）を展開し、動画（.MOV/.mov）を mp4 に変換する。
#        実行中はホストのアクティビティを 10 秒ごとに simple-act.log へ記録する。
#   引数 : "$@" … 入力ファイル（pigz で展開する tar.gz）。user_data がダウンロード済みのもの
#   戻り値: 0=全件変換成功 / ERR=準備・展開の失敗、変換対象0件、変換失敗が1件以上
main() {
  # NOTE: コマンド実行後は必ず rc=$? で戻り値を取得し、エラー制御を行うこと。
  #       set -e は使用しない。戻り値は手動でキャプチャして制御する。
  local rc=0            # 直近コマンドの戻り値
  local input_file=""   # 展開する入力ファイル（引数）
  local mov_files=()    # 変換対象の動画ファイル
  local mov_path=""     # 変換元の動画ファイル
  local mp4=""          # 変換先の mp4 ファイル
  local ng=0            # 変換に失敗した件数

  #--- 準備：タイムゾーンと実行環境の記録 ---
  timedatectl
  sudo timedatectl set-timezone Asia/Tokyo; rc=$?
  [[ ${rc} -eq 0 ]] || log "WARN: set-timezone failed rc=${rc}"
  printf "Hello from EC2!\n"
  printf "Start: %s\n" "$(date '+%Y-%m-%d %T.%3N')"
  printf "I am user: %s\n" "$(whoami)"
  printf "My hostname is: %s\n" "$(hostname -f)"
  lscpu
  free -h
  lsblk
  cat /etc/system-release /etc/os-release
  curl -s http://169.254.169.254/latest/meta-data/instance-type
  printf "\n"

  #--- アクティビティ取得をバックグラウンドで開始（カレント＝ホームに simple-act.log） ---
  cat <<'EOT' > /tmp/simple-act
while true; do
  echo "===== Host Activity Snapshot: $(TZ="Asia/Tokyo" date '+%Y-%m-%d %H:%M:%S') =====";
  echo -e "\n--- Uptime / Load Average ---"; uptime;
  echo -e "\n--- Memory Usage ---"; free -h;
  echo -e "\n--- CPU Usage (mpstat) ---"; mpstat 1 1;
  echo -e "\n--- Disk I/O (iostat) ---"; iostat -xz 1 1;
  echo -e "\n--- Network Connections (ss) ---"; ss -tunap | head -n 10;
  echo -e "\n--- Logged-in Users ---"; who;
  echo -e "\n--- Top 5 CPU Processes ---"; ps aux --sort=-%cpu | head -n 6;
  echo -e "\n--- Top 5 Memory Processes ---"; ps aux --sort=-%mem | head -n 6
  sleep 10
done
EOT
  # 標準エラーもファイルへ向ける（tee のパイプを握ったままにすると、終了時の tee 待ちで止まる。BUG-005）
  bash /tmp/simple-act > simple-act.log 2>&1 &
  ACT_PID=$!   # アクティビティ取得の PID（終了時の trap で参照するためグローバル）
  # 途中で失敗して終了しても、アクティビティ取得を止める
  trap 'kill "${ACT_PID}" 2>/dev/null || true' EXIT
  log "simple-act started pid=${ACT_PID}"

  #--- ffmpeg（静的ビルド）のインストール ---
  pushd /usr/local/bin > /dev/null || return "${ERR}"
  sudo curl -fsSL -o ffmpeg-release-amd64-static.tar.xz \
    https://johnvansickle.com/ffmpeg/releases/ffmpeg-release-amd64-static.tar.xz; rc=$?
  if [[ ${rc} -ne 0 ]]; then log "ERROR: ffmpeg download failed rc=${rc}"; popd > /dev/null; return "${ERR}"; fi
  sudo tar -xJf ffmpeg-release-amd64-static.tar.xz; rc=$?
  if [[ ${rc} -ne 0 ]]; then log "ERROR: ffmpeg extract failed rc=${rc}"; popd > /dev/null; return "${ERR}"; fi
  sudo cp ffmpeg-*-amd64-static/ffmpeg /usr/local/bin/ && sudo chmod +x /usr/local/bin/ffmpeg; rc=$?
  popd > /dev/null
  if [[ ${rc} -ne 0 ]]; then log "ERROR: ffmpeg install failed rc=${rc}"; return "${ERR}"; fi

  #--- pigz（並列展開）・sysstat（mpstat/iostat）のインストール ---
  sudo yum install -y pigz sysstat; rc=$?
  if [[ ${rc} -ne 0 ]]; then log "ERROR: yum install failed rc=${rc}"; return "${ERR}"; fi
  export PATH=${PATH}:/usr/local/bin

  #--- 入力ファイルの展開（ホームディレクトリ） ---
  cd ~ || return "${ERR}"
  log "before extract"; ls -l
  for input_file in "$@"; do
    pigz -dc "${input_file}" | tar -xf -; rc=$?
    if [[ ${rc} -ne 0 ]]; then log "ERROR: extract failed: ${input_file} rc=${rc}"; return "${ERR}"; fi
  done
  log "after extract"; ls -l

  #--- 変換（拡張子の大文字小文字を区別せず一致。0件ならエラー） ---
  shopt -s nullglob nocaseglob
  mov_files=( *.mov )
  shopt -u nullglob nocaseglob
  if [[ ${#mov_files[@]} -eq 0 ]]; then
    log "ERROR: no .MOV/.mov file found in $(pwd)"
    return "${ERR}"
  fi
  for mov_path in "${mov_files[@]}"; do
    mp4="${mov_path%.*}.mp4"
    log "convert: ${mov_path} -> ${mp4}"
    # -nostdin: 標準入力を読まない / -y: 既存ファイルを上書き（端末が無く確認待ちで止まるのを防ぐ）
    ffmpeg -nostdin -y -i "${mov_path}" "${mp4}"; rc=$?
    if [[ ${rc} -ne 0 ]]; then log "ERROR: ffmpeg failed: ${mov_path} rc=${rc}"; ng=$((ng+1)); fi
  done

  #--- 終了：アクティビティ低下時のデータも取ってから停止 ---
  sleep 10
  kill "${ACT_PID}" 2>/dev/null
  log "converted: $(( ${#mov_files[@]} - ng )) / ${#mov_files[@]}, failed: ${ng}"
  log "Done: $(date '+%Y-%m-%d %T.%3N')"
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
# main がどこで return しても、アクティビティ取得を止めてから後処理へ進む（BUG-005）
[[ -n "${ACT_PID}" ]] && kill "${ACT_PID}" 2>/dev/null
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
