#!/usr/bin/env bash
################################################################################
# Terraform インストール／更新スクリプト（Debian 13）
#
# 使い方:
#   ./20260921-debian13-terraform-install-script.sh [バージョン] [公開鍵ファイル]
#     バージョン     : 導入する Terraform のバージョン（例: 1.13.3。任意）
#                      省略時は HashiCorp checkpoint API で最新版を取得する
#     公開鍵ファイル : SHA256SUMS の署名検証に使う HashiCorp の PGP 公開鍵（任意）
#                      省略時は署名検証をスキップする（SHA256 検証は常に行う）
#
# 方針:
#   - releases.hashicorp.com の公式 zip を使う（apt リポジトリは Debian の
#     コードネーム対応に依存するため使わない）
#   - /usr/local/bin/terraform に配置する（AWS CLI と同じ場所）
#
# author      : tsystem
# Last updated: 2026-09-21 23:37:23
#
set -eEuo pipefail

################################################################################
# 定数
readonly SCRIPT_NAME="${0##*/}"                                        # ログ出力用のスクリプト名
readonly BASE_URL="https://releases.hashicorp.com/terraform"          # 公式配布元
readonly CHECKPOINT_URL="https://checkpoint-api.hashicorp.com/v1/check/terraform" # 最新版の問い合わせ先
readonly BIN_DIR="/usr/local/bin"                                     # terraform の配置先
readonly PREREQ_PKGS=(curl unzip jq gnupg ca-certificates)            # 前提パッケージ

################################################################################
# 変数
TF_VERSION="${1:-}"    # 導入するバージョン（空なら最新を取得）
PUBKEY_FILE="${2:-}"   # 署名検証用の公開鍵ファイルパス（空なら署名検証しない）
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
# CPU アーキテクチャを判定し、配布ファイル名用の文字列を返す
#   戻り値（標準出力） : amd64 または arm64
detect_arch() {
    local machine       # uname -m の結果
    machine="$(uname -m)"
    case "$machine" in
        x86_64)  echo "amd64" ;;
        aarch64) echo "arm64" ;;
        *) log ERROR "unsupported architecture: ${machine}"; return 1 ;;
    esac
}

################################################################################
# apt 版 terraform が入っていれば警告して中断する（二重インストール防止）
check_apt_terraform() {
    if dpkg -s terraform >/dev/null 2>&1; then
        log ERROR "apt package 'terraform' is installed. Remove it first: sudo apt-get remove -y terraform"
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
# 導入バージョンを決める（未指定なら最新版を問い合わせる）
#   戻り値（標準出力） : バージョン文字列（例: 1.13.3）
resolve_version() {
    local ver="$TF_VERSION"   # 決定したバージョン
    if [[ -z "$ver" ]]; then
        ver="$(curl -fsSL "$CHECKPOINT_URL" | jq -r '.current_version')"
        log INFO "latest version: ${ver}"
    fi
    if [[ ! "$ver" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        log ERROR "invalid version: '${ver}'"
        return 1
    fi
    echo "$ver"
}

################################################################################
# zip・SHA256SUMS（と署名）をダウンロードする
#   $1 : バージョン
#   $2 : アーキテクチャ（amd64 / arm64）
download_release() {
    local ver="$1"                                    # 対象バージョン
    local arch="$2"                                   # 対象アーキテクチャ
    local url="${BASE_URL}/${ver}"                    # バージョン別の配布ディレクトリ
    local zip="terraform_${ver}_linux_${arch}.zip"    # 本体 zip ファイル名
    local sums="terraform_${ver}_SHA256SUMS"          # チェックサム一覧ファイル名
    log INFO "downloading ${url}/${zip}"
    curl -fsSLo "${WORK_DIR}/${zip}" "${url}/${zip}"
    curl -fsSLo "${WORK_DIR}/${sums}" "${url}/${sums}"
    if [[ -n "$PUBKEY_FILE" ]]; then
        curl -fsSLo "${WORK_DIR}/${sums}.sig" "${url}/${sums}.sig"
    fi
}

################################################################################
# 公開鍵で SHA256SUMS の署名を検証する（PUBKEY_FILE 指定時のみ）
#   $1 : バージョン
verify_signature() {
    local ver="$1"                                    # 対象バージョン
    local sums="${WORK_DIR}/terraform_${ver}_SHA256SUMS"  # 検証対象のチェックサム一覧
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
    log INFO "imported key fingerprint (compare with the official HashiCorp page):"
    GNUPGHOME="$gnupg_home" gpg --fingerprint >&2
    GNUPGHOME="$gnupg_home" gpg --verify "${sums}.sig" "$sums"
    log INFO "signature verification succeeded."
}

################################################################################
# zip の SHA256 を SHA256SUMS と照合する（常に実施）
#   $1 : バージョン
#   $2 : アーキテクチャ
verify_checksum() {
    local ver="$1"                                    # 対象バージョン
    local arch="$2"                                   # 対象アーキテクチャ
    local zip="terraform_${ver}_linux_${arch}.zip"    # 照合する zip ファイル名
    log INFO "verifying SHA256 of ${zip}"
    ( cd "$WORK_DIR" && grep " ${zip}\$" "terraform_${ver}_SHA256SUMS" | sha256sum -c - ) >&2
}

################################################################################
# terraform を配置する（既存があれば上書き）
#   $1 : バージョン
#   $2 : アーキテクチャ
install_terraform() {
    local ver="$1"     # 対象バージョン
    local arch="$2"    # 対象アーキテクチャ
    if [[ -x "${BIN_DIR}/terraform" ]]; then
        log INFO "existing installation found: $("${BIN_DIR}/terraform" version | head -n 1). replacing."
    fi
    unzip -q -o "${WORK_DIR}/terraform_${ver}_linux_${arch}.zip" terraform -d "$WORK_DIR"
    sudo install -m 0755 "${WORK_DIR}/terraform" "${BIN_DIR}/terraform"
}

################################################################################
# インストール結果を確認する
verify_install() {
    hash -r
    local tf_path     # 実際に実行される terraform のパス
    tf_path="$(command -v terraform || true)"
    if [[ "$tf_path" != "${BIN_DIR}/terraform" ]]; then
        log WARN "'terraform' resolves to '${tf_path}', not '${BIN_DIR}/terraform'. check PATH."
    fi
    log INFO "installed: $("${BIN_DIR}/terraform" version | head -n 1)"
}

################################################################################
# メイン処理
main() {
    local arch   # 対象アーキテクチャ
    local ver    # 対象バージョン
    arch="$(detect_arch)"
    log INFO "architecture: ${arch}"

    check_apt_terraform
    install_prereqs
    ver="$(resolve_version)"

    WORK_DIR="$(mktemp -d)"
    download_release "$ver" "$arch"
    verify_signature "$ver"
    verify_checksum "$ver" "$arch"
    install_terraform "$ver" "$arch"
    verify_install

    log INFO "done. (shell completion is not configured; run 'terraform -install-autocomplete' if needed)"
}

main "$@"
