#!/usr/bin/env bash
################################################################################
# AWS CLI v2 インストール／更新スクリプト（Debian 13）
#
# 使い方:
#   ./20260921-debian13-awscli-v2-install-script.sh [公開鍵ファイル]
#     公開鍵ファイル : 署名検証に使う AWS CLI の PGP 公開鍵（任意）
#                      省略時は署名検証をスキップする
#
# author      : tsystem
# Last updated: 2026-09-21 15:10:58
#
set -eEuo pipefail

################################################################################
# 定数
readonly SCRIPT_NAME="${0##*/}"                     # ログ出力用のスクリプト名
readonly BASE_URL="https://awscli.amazonaws.com" # 公式インストーラ配布元
readonly INSTALL_DIR="/usr/local/aws-cli"        # AWS CLI 本体のインストール先
readonly BIN_DIR="/usr/local/bin"                # aws / aws_completer のリンク配置先
readonly PREREQ_PKGS=(curl unzip less groff-base gnupg ca-certificates) # 前提パッケージ

################################################################################
# 変数
PUBKEY_FILE="${1:-}"   # 署名検証用の公開鍵ファイルパス（空なら検証しない）
WORK_DIR=""            # 作業用一時ディレクトリ（EXIT 時に削除）

################################################################################
# ログを標準エラーへ出力する
#   $1 : ログレベル（INFO / WARN / ERROR）
#   $2 : メッセージ
log() {
    local level="$1"   # ログレベル
    local msg="$2"     # 出力するメッセージ
    printf '%s [%s] %s: %s\n' "$(date '+%F %T')" "$level" "$SCRIPT_NAME" "$msg" >&2
}

################################################################################
# 終了時の後片付け（作業ディレクトリ削除）
cleanup() {
    if [[ -n "$WORK_DIR" && -d "$WORK_DIR" ]]; then
        rm -rf "$WORK_DIR"
    fi
}

################################################################################
# エラー発生時のハンドラ
#   $1 : エラーが発生した行番号
#   $2 : 終了ステータス
on_error() {
    local line="$1"    # エラー発生行
    local rc="$2"      # 終了ステータス
    log ERROR "line ${line}: command failed (exit ${rc})"
}

trap 'on_error $LINENO $?' ERR
trap cleanup EXIT
trap 'log WARN "interrupted"; exit 130' INT TERM

################################################################################
# CPU アーキテクチャを判定し、インストーラのファイル名用文字列を返す
#   戻り値（標準出力） : x86_64 または aarch64
detect_arch() {
    local machine       # uname -m の結果
    machine="$(uname -m)"
    case "$machine" in
        x86_64|aarch64) echo "$machine" ;;
        *) log ERROR "unsupported architecture: ${machine}"; return 1 ;;
    esac
}

################################################################################
# apt 版 awscli が入っていれば警告して中断する（二重インストール防止）
check_apt_awscli() {
    if dpkg -s awscli >/dev/null 2>&1; then
        log ERROR "apt package 'awscli' is installed. Remove it first: sudo apt-get remove -y awscli"
        return 1
    fi
}

################################################################################
# 前提パッケージを導入する
install_prereqs() {
    log INFO "installing prerequisites: ${PREREQ_PKGS[*]}"
    sudo apt-get update -qq
    sudo apt-get install -y -qq "${PREREQ_PKGS[@]}"
}

################################################################################
# インストーラ zip（と署名）をダウンロードする
#   $1 : アーキテクチャ（x86_64 / aarch64）
download_installer() {
    local arch="$1"                                       # 対象アーキテクチャ
    local url="${BASE_URL}/awscli-exe-linux-${arch}.zip"  # ダウンロード URL
    log INFO "downloading ${url}"
    curl -fsSLo "${WORK_DIR}/awscliv2.zip" "$url"
    if [[ -n "$PUBKEY_FILE" ]]; then
        curl -fsSLo "${WORK_DIR}/awscliv2.zip.sig" "${url}.sig"
    fi
}

################################################################################
# 公開鍵でインストーラの署名を検証する（PUBKEY_FILE 指定時のみ）
verify_signature() {
    if [[ -z "$PUBKEY_FILE" ]]; then
        log WARN "public key not specified. skipping signature verification."
        return 0
    fi
    if [[ ! -r "$PUBKEY_FILE" ]]; then
        log ERROR "public key file not readable: ${PUBKEY_FILE}"
        return 1
    fi

    local gnupg_home="${WORK_DIR}/gnupg"   # 検証専用の一時鍵束（普段の鍵束を汚さない）
    mkdir -m 700 "$gnupg_home"
    GNUPGHOME="$gnupg_home" gpg --quiet --import "$PUBKEY_FILE"
    log INFO "imported key fingerprint (compare with the official AWS page):"
    GNUPGHOME="$gnupg_home" gpg --fingerprint >&2
    GNUPGHOME="$gnupg_home" gpg --verify "${WORK_DIR}/awscliv2.zip.sig" "${WORK_DIR}/awscliv2.zip"
    log INFO "signature verification succeeded."
}

################################################################################
# インストール（既存があれば更新）を実行する
install_awscli() {
    local update_opt=()   # 既存インストールがある場合の --update オプション
    if [[ -x "${BIN_DIR}/aws" ]]; then
        log INFO "existing installation found: $("${BIN_DIR}/aws" --version 2>&1). updating."
        update_opt=(--update)
    fi

    unzip -q "${WORK_DIR}/awscliv2.zip" -d "$WORK_DIR"
    sudo "${WORK_DIR}/aws/install" \
        --bin-dir "$BIN_DIR" \
        --install-dir "$INSTALL_DIR" \
        "${update_opt[@]}"
}

################################################################################
# インストール結果を確認する
verify_install() {
    hash -r
    local aws_path    # 実際に実行される aws のパス
    aws_path="$(command -v aws || true)"
    if [[ "$aws_path" != "${BIN_DIR}/aws" ]]; then
        log WARN "'aws' resolves to '${aws_path}', not '${BIN_DIR}/aws'. check PATH."
    fi
    log INFO "installed: $("${BIN_DIR}/aws" --version 2>&1)"
}

################################################################################
# メイン処理
main() {
    local arch   # 対象アーキテクチャ
    arch="$(detect_arch)"
    log INFO "architecture: ${arch}"

    check_apt_awscli
    install_prereqs

    WORK_DIR="$(mktemp -d)"
    download_installer "$arch"
    verify_signature
    install_awscli
    verify_install

    log INFO "done. (bash completion is not configured by this script; see the manual §4.7)"
}

main "$@"
