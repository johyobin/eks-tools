#!/bin/bash

# =============================================================================
# EKS Tools Setup Script (Production Ready)
# Description: AWS EKS 관련 도구들을 안전하게 설치하는 스크립트
# Author: Updated for production use
# Version: 2.1
# =============================================================================

set -euo pipefail

# 전역 변수
readonly SCRIPT_NAME="$(basename "$0")"
readonly SCRIPT_VERSION="2.1"
readonly LOG_FILE="/tmp/eks-tools-setup-$(date +%Y%m%d-%H%M%S).log"

# 색상 설정
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

# 전역 변수 초기화
REGION=""
CLUSTER_NAME=""
TEMP_DIR=""

# 로그 함수들
log_info() {
    local message="$1"
    echo -e "${BLUE}[INFO]${NC} $message" | tee -a "$LOG_FILE"
}

log_success() {
    local message="$1"
    echo -e "${GREEN}[SUCCESS]${NC} $message" | tee -a "$LOG_FILE"
}

log_warning() {
    local message="$1"
    echo -e "${YELLOW}[WARNING]${NC} $message" | tee -a "$LOG_FILE"
}

log_error() {
    local message="$1"
    echo -e "${RED}[ERROR]${NC} $message" | tee -a "$LOG_FILE" >&2
}

# 정리 함수
cleanup() {
    if [[ -n "$TEMP_DIR" && -d "$TEMP_DIR" ]]; then
        log_info "임시 파일을 정리하는 중..."
        rm -rf "$TEMP_DIR"
    fi
}

# 에러 핸들러
error_handler() {
    local line_no="$1"
    local exit_code="$2"
    log_error "스크립트 실행 중 오류 발생 (라인: $line_no, 종료코드: $exit_code)"
    log_info "자세한 로그는 $LOG_FILE 에서 확인할 수 있습니다."
    cleanup
    exit "$exit_code"
}

# 시그널 핸들러
signal_handler() {
    log_warning "사용자에 의해 스크립트가 중단되었습니다."
    cleanup
    exit 130
}

# 트랩 설정
trap 'error_handler $LINENO $?' ERR
trap signal_handler INT TERM
trap cleanup EXIT

# 사용자 확인 함수
confirm_action() {
    local message="$1"
    local default="${2:-n}"

    while true; do
        if [[ "$default" == "y" ]]; then
            read -p "$message (Y/n): " -r response
            response="${response:-y}"
        else
            read -p "$message (y/N): " -r response
            response="${response:-n}"
        fi

        case "$response" in
            [Yy]|[Yy][Ee][Ss]) return 0 ;;
            [Nn]|[Nn][Oo]) return 1 ;;
            *) echo "y 또는 n을 입력해주세요." ;;
        esac
    done
}

# OS 및 아키텍처 확인
detect_os_arch() {
    if [[ "$OSTYPE" != "linux-gnu"* ]]; then
        log_error "이 스크립트는 Linux에서만 지원됩니다. (현재 OS: $OSTYPE)"
        exit 1
    fi

    local arch
    arch=$(uname -m)
    if [[ "$arch" != "x86_64" ]]; then
        log_error "이 스크립트는 x86_64 아키텍처에서만 지원됩니다. (현재: $arch)"
        exit 1
    fi

    log_success "OS 및 아키텍처 확인 완료: Linux x86_64"
}

# 네트워크 연결 확인
check_network() {
    log_info "네트워크 연결을 확인하는 중..."

    local test_urls=(
        "https://dl.k8s.io"
        "https://api.github.com"
        "https://raw.githubusercontent.com"
    )

    for url in "${test_urls[@]}"; do
        if ! curl -sSf --connect-timeout 10 --max-time 30 "$url" >/dev/null 2>&1; then
            log_error "네트워크 연결 실패: $url"
            log_error "인터넷 연결을 확인하고 방화벽 설정을 점검해주세요."
            exit 1
        fi
    done

    log_success "네트워크 연결 확인 완료"
}

# 필수 요구사항 확인
check_prerequisites() {
    log_info "시스템 요구사항을 확인하는 중..."

    # OS 및 아키텍처 확인
    detect_os_arch

    # 네트워크 확인
    check_network

    # sudo 권한 확인 (비밀번호 없이)
    if ! sudo -n true 2>/dev/null; then
        log_warning "이 스크립트는 sudo 권한이 필요합니다."
        if ! confirm_action "sudo 권한을 사용하여 시스템 패키지를 설치하시겠습니까?"; then
            log_info "사용자가 설치를 취소했습니다."
            exit 0
        fi

        # sudo 권한 테스트
        if ! sudo true; then
            log_error "sudo 권한을 얻을 수 없습니다."
            exit 1
        fi
    fi

    # 필수 명령어 확인
    local required_commands=("curl" "tar" "sha256sum" "grep" "sed")
    for cmd in "${required_commands[@]}"; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            log_error "필수 명령어 '$cmd'가 설치되어 있지 않습니다."
            exit 1
        fi
    done

    # AWS CLI 확인 (선택사항)
    if ! command -v aws >/dev/null 2>&1; then
        log_warning "AWS CLI가 설치되어 있지 않습니다."
        log_info "EKS 클러스터 연결을 위해서는 AWS CLI가 필요합니다."
        log_info "설치 방법: https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2-linux.html"
    fi

    # /usr/local/bin 쓰기 권한 확인
    if [[ ! -w "/usr/local/bin" ]]; then
        if ! sudo test -w "/usr/local/bin" 2>/dev/null; then
            log_error "/usr/local/bin 디렉터리에 쓰기 권한이 없습니다."
            exit 1
        fi
    fi

    log_success "시스템 요구사항 확인 완료"
}

# 환경 변수 설정
setup_environment() {
    log_info "환경 변수를 설정하는 중..."

    # 리전 입력
    while true; do
        read -p "AWS 리전을 입력하세요 (예: us-west-2): " -r input_region
        if [[ -n "$input_region" && "$input_region" =~ ^[a-z0-9-]+$ ]]; then
            REGION="$input_region"
            break
        else
            echo "올바른 AWS 리전을 입력해주세요. (예: us-west-2, eu-west-1)"
        fi
    done

    # 클러스터 이름 입력
    echo ""
    echo "EKS 클러스터 이름을 입력하세요 (건너뛰려면 Enter):"
    read -p "클러스터 이름: " -r input_cluster

    if [[ -n "$input_cluster" ]]; then
        if [[ "$input_cluster" =~ ^[a-zA-Z0-9-]+$ ]]; then
            CLUSTER_NAME="$input_cluster"
        else
            log_warning "클러스터 이름에 잘못된 문자가 포함되어 있습니다. 나중에 수동으로 설정해주세요."
            CLUSTER_NAME=""
        fi
    else
        log_info "클러스터 이름을 나중에 설정하겠습니다."
        CLUSTER_NAME=""
    fi

    # bashrc 백업
    local bashrc_file="$HOME/.bashrc"
    if [[ -f "$bashrc_file" ]]; then
        cp "$bashrc_file" "${bashrc_file}.backup-$(date +%Y%m%d-%H%M%S)"
        log_info "기존 .bashrc를 백업했습니다."
    fi

    # 기존 설정 제거 (안전하게)
    if [[ -f "$bashrc_file" ]]; then
        sed -i.bak '/^export AWS_REGION=/d; /^export CLUSTER_NAME=/d' "$bashrc_file"
    fi

    # 새 설정 추가
    {
        echo ""
        echo "# EKS Tools Configuration - Added by $SCRIPT_NAME v$SCRIPT_VERSION on $(date)"
        echo "export AWS_REGION=\"$REGION\""
        if [[ -n "$CLUSTER_NAME" ]]; then
            echo "export CLUSTER_NAME=\"$CLUSTER_NAME\""
        fi
        echo ""
    } >> "$bashrc_file"

    log_success "환경 변수 설정 완료 (리전: $REGION, 클러스터: ${CLUSTER_NAME:-'미설정'})"
}

# 버전 비교 함수
version_gt() {
    test "$(printf '%s\n' "$@" | sort -V | head -n 1)" != "$1"
}

# kubectl 설치
install_kubectl() {
    log_info "kubectl 설치를 시작합니다..."

    # 이미 설치되어 있는지 확인
    if command -v kubectl >/dev/null 2>&1; then
        local current_version
        current_version=$(kubectl version --client -o json 2>/dev/null | grep -o '"gitVersion":"[^"]*' | cut -d'"' -f4 || echo "unknown")
        log_warning "kubectl이 이미 설치되어 있습니다 (버전: $current_version)"
        if ! confirm_action "기존 kubectl을 최신 버전으로 업데이트하시겠습니까?"; then
            log_info "kubectl 설치를 건너뜁니다."
            return 0
        fi
    fi

    # 임시 디렉터리 생성
    TEMP_DIR=$(mktemp -d)
    cd "$TEMP_DIR"

    # 최신 안정 버전 가져오기
    log_info "최신 kubectl 버전을 확인하는 중..."
    local kubectl_version
    kubectl_version=$(curl -sSL --connect-timeout 10 --max-time 30 --retry 3 \
        https://dl.k8s.io/release/stable.txt)

    if [[ -z "$kubectl_version" || ! "$kubectl_version" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        log_error "kubectl 버전 정보를 가져올 수 없습니다."
        return 1
    fi

    log_info "kubectl 버전 $kubectl_version 다운로드 중..."

    # kubectl 바이너리 다운로드
    if ! curl -sSL --connect-timeout 10 --max-time 60 --retry 3 -o kubectl \
        "https://dl.k8s.io/release/${kubectl_version}/bin/linux/amd64/kubectl"; then
        log_error "kubectl 다운로드에 실패했습니다."
        return 1
    fi

    # 체크섬 파일 다운로드
    if ! curl -sSL --connect-timeout 10 --max-time 30 --retry 3 -o kubectl.sha256 \
        "https://dl.k8s.io/release/${kubectl_version}/bin/linux/amd64/kubectl.sha256"; then
        log_error "kubectl 체크섬 파일 다운로드에 실패했습니다."
        return 1
    fi

    # 체크섬 검증
    log_info "kubectl 체크섬을 검증하는 중..."
    if ! echo "$(cat kubectl.sha256)  kubectl" | sha256sum --check --quiet; then
        log_error "kubectl 체크섬 검증에 실패했습니다."
        return 1
    fi

    # 파일 크기 확인 (최소 크기 체크)
    local file_size
    file_size=$(stat -c%s kubectl)
    if [[ "$file_size" -lt 10000000 ]]; then  # 10MB 미만이면 의심스러움
        log_error "다운로드된 kubectl 파일 크기가 비정상적입니다 ($file_size bytes)."
        return 1
    fi

    # 실행 권한 부여 및 설치
    chmod +x kubectl

    # 백업 및 설치
    if [[ -f "/usr/local/bin/kubectl" ]]; then
        sudo cp "/usr/local/bin/kubectl" "/usr/local/bin/kubectl.backup-$(date +%Y%m%d-%H%M%S)"
    fi

    sudo mv kubectl /usr/local/bin/

    # 설치 확인
    if kubectl version --client >/dev/null 2>&1; then
        local installed_version
        installed_version=$(kubectl version --client -o json 2>/dev/null | grep -o '"gitVersion":"[^"]*' | cut -d'"' -f4 2>/dev/null || kubectl version --client --short 2>/dev/null | cut -d' ' -f3 || echo "$kubectl_version")
        log_success "kubectl 설치 완료: $installed_version"
    else
        log_error "kubectl 설치 검증에 실패했습니다."
        return 1
    fi
}

# eksctl 설치
install_eksctl() {
    log_info "eksctl 설치를 시작합니다..."

    # 이미 설치되어 있는지 확인
    if command -v eksctl >/dev/null 2>&1; then
        local current_version
        current_version=$(eksctl version 2>/dev/null | head -n1 || echo "unknown")
        log_warning "eksctl이 이미 설치되어 있습니다 (버전: $current_version)"
        if ! confirm_action "기존 eksctl을 최신 버전으로 업데이트하시겠습니까?"; then
            log_info "eksctl 설치를 건너뜁니다."
            return 0
        fi
    fi

    # 임시 디렉터리 생성 (이미 존재하면 재사용)
    if [[ -z "$TEMP_DIR" ]]; then
        TEMP_DIR=$(mktemp -d)
    fi
    cd "$TEMP_DIR"

    # 최신 버전 정보 가져오기
    log_info "최신 eksctl 버전을 확인하는 중..."
    local eksctl_version
    eksctl_version=$(curl -sSL --connect-timeout 10 --max-time 30 --retry 3 \
        "https://api.github.com/repos/weaveworks/eksctl/releases/latest" | \
        grep '"tag_name":' | sed -E 's/.*"v([^"]+)".*/\1/')

    if [[ -z "$eksctl_version" || ! "$eksctl_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        log_error "eksctl 버전 정보를 가져올 수 없습니다."
        return 1
    fi

    log_info "eksctl 버전 v$eksctl_version 다운로드 중..."

    # eksctl 다운로드 및 압축 해제
    local download_url="https://github.com/weaveworks/eksctl/releases/download/v${eksctl_version}/eksctl_$(uname -s)_amd64.tar.gz"
    if ! curl -sSL --connect-timeout 10 --max-time 120 --retry 3 "$download_url" | tar xz; then
        log_error "eksctl 다운로드에 실패했습니다."
        return 1
    fi

    # 다운로드된 파일 확인
    if [[ ! -f "eksctl" ]]; then
        log_error "eksctl 바이너리를 찾을 수 없습니다."
        return 1
    fi

    # 파일 크기 확인
    local file_size
    file_size=$(stat -c%s eksctl)
    if [[ "$file_size" -lt 5000000 ]]; then  # 5MB 미만이면 의심스러움
        log_error "다운로드된 eksctl 파일 크기가 비정상적입니다 ($file_size bytes)."
        return 1
    fi

    # 실행 권한 부여 및 설치
    chmod +x eksctl

    # 백업 및 설치
    if [[ -f "/usr/local/bin/eksctl" ]]; then
        sudo cp "/usr/local/bin/eksctl" "/usr/local/bin/eksctl.backup-$(date +%Y%m%d-%H%M%S)"
    fi

    sudo mv eksctl /usr/local/bin/

    # 설치 확인
    if eksctl version >/dev/null 2>&1; then
        local installed_version
        installed_version=$(eksctl version 2>/dev/null | head -n1)
        log_success "eksctl 설치 완료: $installed_version"
    else
        log_error "eksctl 설치 검증에 실패했습니다."
        return 1
    fi
}

# Helm 설치
install_helm() {
    log_info "Helm 설치를 시작합니다..."

    # 이미 설치되어 있는지 확인
    if command -v helm >/dev/null 2>&1; then
        local current_version
        current_version=$(helm version --short 2>/dev/null | cut -d':' -f2 | tr -d ' ' || echo "unknown")
        log_warning "Helm이 이미 설치되어 있습니다 (버전: $current_version)"
        if ! confirm_action "기존 Helm을 최신 버전으로 업데이트하시겠습니까?"; then
            log_info "Helm 설치를 건너뜁니다."
            return 0
        fi
    fi

    # 임시 디렉터리 생성 (이미 존재하면 재사용)
    if [[ -z "$TEMP_DIR" ]]; then
        TEMP_DIR=$(mktemp -d)
    fi
    cd "$TEMP_DIR"

    # Helm 최신 버전 정보 가져오기
    log_info "최신 Helm 버전을 확인하는 중..."
    local helm_version
    helm_version=$(curl -sSL --connect-timeout 10 --max-time 30 --retry 3 \
        "https://api.github.com/repos/helm/helm/releases/latest" | \
        grep '"tag_name":' | sed -E 's/.*"v([^"]+)".*/\1/' 2>/dev/null)

    if [[ -z "$helm_version" || ! "$helm_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        log_warning "Helm 버전 정보를 가져올 수 없습니다. 설치 스크립트를 사용합니다."
        helm_version="latest"
    else
        log_info "Helm 버전 v$helm_version을 설치합니다."
    fi

    # 직접 바이너리 다운로드 방식으로 변경
    log_info "Helm 바이너리를 다운로드하는 중..."
    local os="linux"
    local arch="amd64"

    if [[ "$helm_version" != "latest" ]]; then
        local download_url="https://get.helm.sh/helm-v${helm_version}-${os}-${arch}.tar.gz"
    else
        # 최신 버전을 위한 일반적인 URL
        local download_url="https://get.helm.sh/helm-v3.16.4-${os}-${arch}.tar.gz"
    fi

    if ! curl -sSL --connect-timeout 10 --max-time 120 --retry 3 -o helm.tar.gz "$download_url"; then
        log_warning "직접 다운로드에 실패했습니다. 설치 스크립트를 시도합니다."

        # 대안: 공식 설치 스크립트 사용
        log_info "Helm 공식 설치 스크립트를 다운로드하는 중..."
        if ! curl -sSL --connect-timeout 10 --max-time 60 --retry 3 \
            -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3; then
            log_error "Helm 설치 스크립트 다운로드에 실패했습니다."
            return 1
        fi

        # 스크립트 내용 간단 검증
        if ! grep -q "HELM_INSTALL_DIR" get_helm.sh; then
            log_error "다운로드된 Helm 설치 스크립트가 올바르지 않습니다."
            return 1
        fi

        # 스크립트 실행 (더 안전한 방식)
        chmod +x get_helm.sh
        log_info "Helm 설치 스크립트를 실행합니다..."
        if ! HELM_INSTALL_DIR="/usr/local/bin" bash get_helm.sh --no-sudo >/dev/null 2>&1; then
            log_error "Helm 설치 스크립트 실행에 실패했습니다."
            return 1
        fi

        # sudo로 권한 설정 (필요한 경우)
        if [[ -f "./linux-amd64/helm" ]]; then
            sudo mv ./linux-amd64/helm /usr/local/bin/helm
            sudo chmod +x /usr/local/bin/helm
        elif [[ -f "/usr/local/bin/helm" ]]; then
            sudo chmod +x /usr/local/bin/helm
        else
            log_error "Helm 바이너리를 찾을 수 없습니다."
            return 1
        fi
    else
        # 직접 다운로드 성공한 경우
        log_info "Helm 압축을 해제하는 중..."
        if ! tar -zxf helm.tar.gz; then
            log_error "Helm 압축 해제에 실패했습니다."
            return 1
        fi

        # 바이너리 찾기 및 설치
        if [[ -f "${os}-${arch}/helm" ]]; then
            chmod +x "${os}-${arch}/helm"

            # 백업
            if [[ -f "/usr/local/bin/helm" ]]; then
                sudo cp "/usr/local/bin/helm" "/usr/local/bin/helm.backup-$(date +%Y%m%d-%H%M%S)"
            fi

            sudo mv "${os}-${arch}/helm" /usr/local/bin/helm
        else
            log_error "Helm 바이너리를 찾을 수 없습니다."
            return 1
        fi
    fi

    # 설치 확인
    if command -v helm >/dev/null 2>&1 && helm version >/dev/null 2>&1; then
        local installed_version
        installed_version=$(helm version --short 2>/dev/null | cut -d'+' -f1 | sed 's/v//' || echo "unknown")
        log_success "Helm 설치 완료: v$installed_version"
    else
        log_error "Helm 설치 검증에 실패했습니다."
        return 1
    fi
}

# kubectl 자동완성 설정
setup_kubectl_completion() {
    log_info "kubectl bash 자동완성을 설정하는 중..."

    local bashrc_file="$HOME/.bashrc"
    local completion_line="source <(kubectl completion bash)"

    # 이미 설정되어 있는지 확인
    if grep -q "kubectl completion bash" "$bashrc_file" 2>/dev/null; then
        log_info "kubectl 자동완성이 이미 설정되어 있습니다."
        return 0
    fi

    # kubectl이 설치되어 있는지 확인
    if ! command -v kubectl >/dev/null 2>&1; then
        log_warning "kubectl이 설치되어 있지 않아 자동완성을 설정할 수 없습니다."
        return 1
    fi

    # bash-completion 패키지 확인 및 안내
    if ! dpkg -l bash-completion >/dev/null 2>&1 && ! rpm -qa | grep -q bash-completion; then
        log_warning "bash-completion 패키지가 설치되어 있지 않을 수 있습니다."
        log_info "자동완성이 작동하지 않는다면 다음 명령어로 설치하세요:"
        log_info "  Ubuntu/Debian: sudo apt-get install bash-completion"
        log_info "  CentOS/RHEL: sudo yum install bash-completion"
    fi

    # 자동완성 설정 추가
    {
        echo ""
        echo "# kubectl completion - Added by $SCRIPT_NAME v$SCRIPT_VERSION"
        echo "$completion_line"
        echo ""
    } >> "$bashrc_file"

    log_success "kubectl 자동완성 설정 완료 (새 터미널에서 적용됨)"
}

# kubeconfig 설정
setup_kubeconfig() {
    if [[ -z "$CLUSTER_NAME" ]]; then
        log_warning "클러스터 이름이 설정되지 않았습니다."
        log_info "나중에 다음 명령어로 kubeconfig를 설정하세요:"
        log_info "  aws eks update-kubeconfig --region $REGION --name <CLUSTER_NAME>"
        return 0
    fi

    log_info "EKS 클러스터 연결을 설정하는 중..."

    # AWS CLI 설치 확인
    if ! command -v aws >/dev/null 2>&1; then
        log_error "AWS CLI가 설치되어 있지 않습니다."
        log_info "AWS CLI를 먼저 설치하고 설정하세요:"
        log_info "  https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2-linux.html"
        return 1
    fi

    # AWS 자격 증명 확인
    log_info "AWS 자격 증명을 확인하는 중..."
    if ! aws sts get-caller-identity >/dev/null 2>&1; then
        log_error "AWS 자격 증명이 설정되어 있지 않습니다."
        log_info "다음 명령어로 AWS CLI를 설정하세요:"
        log_info "  aws configure"
        return 1
    fi

    # EKS 클러스터 존재 확인
    log_info "EKS 클러스터 존재를 확인하는 중..."
    if ! aws eks describe-cluster --region "$REGION" --name "$CLUSTER_NAME" >/dev/null 2>&1; then
        log_error "EKS 클러스터 '$CLUSTER_NAME'을 찾을 수 없습니다."
        log_info "클러스터 이름과 리전을 확인하거나, 다음 명령어로 클러스터 목록을 확인하세요:"
        log_info "  aws eks list-clusters --region $REGION"
        return 1
    fi

    # kubeconfig 업데이트
    log_info "kubeconfig를 업데이트하는 중... (클러스터: $CLUSTER_NAME, 리전: $REGION)"
    if aws eks update-kubeconfig --region "$REGION" --name "$CLUSTER_NAME"; then
        log_success "kubeconfig 설정 완료"

        # 연결 테스트
        log_info "클러스터 연결을 테스트하는 중..."
        if timeout 30 kubectl cluster-info >/dev/null 2>&1; then
            log_success "EKS 클러스터 연결 확인 완료"
        else
            log_warning "EKS 클러스터에 연결할 수 없습니다."
            log_info "가능한 원인:"
            log_info "  - 클러스터가 프라이빗 엔드포인트만 활성화되어 있음"
            log_info "  - VPC/보안그룹 설정으로 인한 네트워크 제한"
            log_info "  - IAM 권한 부족"
            log_info "수동으로 'kubectl get nodes' 명령어를 실행해보세요."
        fi
    else
        log_error "kubeconfig 설정에 실패했습니다."
        return 1
    fi
}

# 설치 요약 출력
print_summary() {
    echo ""
    echo "=================================================="
    log_success "모든 EKS 도구 설치가 완료되었습니다!"
    echo "=================================================="
    echo ""

    echo "설치된 도구들:"
    if command -v kubectl >/dev/null 2>&1; then
        local kubectl_version
        kubectl_version=$(kubectl version --client -o json 2>/dev/null | grep -o '"gitVersion":"[^"]*' | cut -d'"' -f4 2>/dev/null || kubectl version --client --short 2>/dev/null | cut -d'' -f3 2>/dev/null || echo "설치됨")
        echo "  ✅ kubectl: $kubectl_version"
    fi

    if command -v eksctl >/dev/null 2>&1; then
        local eksctl_version
        eksctl_version=$(eksctl version 2>/dev/null | head -n1 | cut -d' ' -f2 2>/dev/null || echo "설치됨")
        echo "  ✅ eksctl: $eksctl_version"
    fi

    if command -v helm >/dev/null 2>&1; then
        local helm_version
        helm_version=$(helm version --short 2>/dev/null | cut -d'+' -f1 2>/dev/null || echo "설치됨")
        echo "  ✅ Helm: $helm_version"
    fi

    echo ""
    echo "환경 변수:"
    echo "  - AWS_REGION: $REGION"
    echo "  - CLUSTER_NAME: ${CLUSTER_NAME:-'미설정'}"

    echo ""
    echo "다음 단계:"
    if [[ -z "$CLUSTER_NAME" ]]; then
        echo "  1. EKS 클러스터를 생성하거나 기존 클러스터 이름을 확인하세요"
        echo "  2. 다음 명령어로 kubeconfig를 설정하세요:"
        echo "     aws eks update-kubeconfig --region $REGION --name <CLUSTER_NAME>"
    fi
    echo "  - 새 터미널을 열거나 'source ~/.bashrc'를 실행하여 변경사항을 적용하세요"
    echo "  - 'kubectl get nodes' 명령어로 클러스터 연결을 확인하세요"
    echo ""

    log_info "설치 로그: $LOG_FILE"
    log_info "백업 파일들은 .backup-* 형태로 저장되어 있습니다."
}

# 메인 실행 함수
main() {
    echo "=================================================="
    echo "🚀 EKS Tools Setup Script v$SCRIPT_VERSION"
    echo "=================================================="
    echo ""

    log_info "이 스크립트는 다음 도구들을 설치합니다:"
    echo "  - kubectl (Kubernetes CLI)"
    echo "  - eksctl (EKS CLI)"
    echo "  - Helm (Kubernetes 패키지 매니저)"
    echo ""
    echo "설치 로그는 $LOG_FILE 에 저장됩니다."
    echo ""

    if ! confirm_action "설치를 시작하시겠습니까?"; then
        log_info "사용자가 설치를 취소했습니다."
        exit 0
    fi

    # 단계별 실행
    check_prerequisites
    setup_environment

    echo ""
    log_info "=== 도구 설치 시작 ==="

    # 각 설치 단계를 개별적으로 실행하여 한 단계 실패가 전체에 영향주지 않도록 함
    local install_success=true

    if ! install_kubectl; then
        log_error "kubectl 설치에 실패했습니다."
        install_success=false
    fi

    if ! install_eksctl; then
        log_error "eksctl 설치에 실패했습니다."
        install_success=false
    fi

    if ! install_helm; then
        log_error "Helm 설치에 실패했습니다."
        install_success=false
    fi

    # 자동완성은 실패해도 전체에 영향 없음
    setup_kubectl_completion || log_warning "kubectl 자동완성 설정에 실패했습니다."

    # kubeconfig 설정도 실패해도 전체에 영향 없음
    setup_kubeconfig || log_warning "kubeconfig 설정에 실패했습니다."

    if [[ "$install_success" == "false" ]]; then
        log_error "일부 도구 설치에 실패했습니다. 로그를 확인하세요: $LOG_FILE"
        exit 1
    fi

    print_summary
}

# 스크립트가 직접 실행될 때만 main 함수 호출
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi