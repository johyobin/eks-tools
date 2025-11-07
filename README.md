# 🧰 EKS Tools Setup Script

AWS EKS 환경을 위한 CLI 도구를 자동으로 설치하고 구성하는 **Bash 스크립트**입니다.  
`kubectl`, `krew`, `ctx`, `neat`, `eksctl`, `Helm` 등 필수 도구를 한 번에 설치하고 환경을 세팅합니다.

---

## 🚀 주요 기능

| 기능 | 설명 |
|------|------|
| ✅ **kubectl 설치 및 검증** | 최신 안정 버전 자동 설치 및 체크섬 검증 |
| ✅ **krew 자동 설치** | kubectl 플러그인 매니저 설치 및 PATH 구성 |
| ✅ **플러그인 설치 (ctx, neat)** | 클러스터 전환(`ctx`), YAML 정리(`neat`) |
| ✅ **eksctl 설치** | EKS 클러스터 생성/관리 도구 |
| ✅ **Helm 설치** | Kubernetes 패키지 매니저 |
| ✅ **bash 자동완성 설정** | `alias k=kubectl`, bash-completion |
| ✅ **AWS 환경 변수 자동 설정** | `AWS_REGION`, `CLUSTER_NAME` 자동 추가 |
| ✅ **EKS 클러스터 연결 설정** | `aws eks update-kubeconfig` 자동 수행 |
| ✅ **로그 관리 및 복구 기능** | `/tmp/eks-tools-setup-*.log` 로깅 및 자동 정리 |

---

## 📦 설치되는 도구 목록

| 도구 | 설명 |
|------|------|
| **kubectl** | Kubernetes CLI |
| **krew** | kubectl 플러그인 매니저 |
| **kubectl-ctx** | 컨텍스트 전환 플러그인 |
| **kubectl-neat** | YAML 출력 정리 플러그인 |
| **eksctl** | EKS 클러스터 관리 CLI |
| **Helm** | Kubernetes 패키지 매니저 |

---

## 🧩 설치 방법

### 1. 리포지토리 클론
```bash
git clone https://github.com/johyobin/eks-tools.git
cd eks-tools
```

### 2. 실행 권한 부여
```bash
chmod +x setup-eks-tools.sh
```

### 3. 스크립트 실행
```bash
./setup-eks-tools.sh
```

> ⚠️ 실행 중 `sudo` 권한이 필요할 수 있으며, AWS CLI 설정(`aws configure`)이 완료되어 있어야 합니다.

---

## ⚙️ 주요 단계

1. **시스템 환경 확인**
   - OS, 아키텍처, sudo, curl, tar, 네트워크 등 필수 항목 점검  
2. **AWS 환경 변수 설정**
   - `AWS_REGION`, `CLUSTER_NAME` 입력 및 `.bashrc`에 자동 등록  
3. **도구 설치**
   - kubectl → krew → ctx/neat → eksctl → Helm 순서로 설치  
4. **자동완성 및 alias 추가**
   - `alias k=kubectl`, `complete -F __start_kubectl k` 설정  
5. **kubeconfig 설정**
   - `aws eks update-kubeconfig` 실행 및 연결 검증  
6. **결과 요약**
   - 설치된 버전 및 환경 변수 출력

---

## 🧾 실행 결과 예시

```
==================================================
[SUCCESS] 모든 EKS 도구 설치가 완료되었습니다!
==================================================

설치된 도구들:
  ✅ kubectl: v1.31.0
  ✅ krew: v0.4.5
  ✅ kubectl-ctx (via krew)
  ✅ kubectl-neat (via krew)
  ✅ eksctl: v0.190.0
  ✅ Helm: v3.16.4

환경 변수:
  - AWS_REGION: ap-northeast-2
  - CLUSTER_NAME: dev-cluster

다음 단계:
  1. EKS 클러스터 연결 테스트: `kubectl get nodes`
  2. 필요 시 kubeconfig 재설정:  
     `aws eks update-kubeconfig --region ap-northeast-2 --name dev-cluster`
```

---

## 🧰 로그 파일

- 모든 실행 로그는 `/tmp/eks-tools-setup-YYYYMMDD-HHMMSS.log`에 저장됩니다.
- 에러 발생 시 이 로그 파일을 참고하세요.

---

## ⚠️ 주의사항

- Linux (x86_64) 환경만 지원됩니다.
- `bash`, `curl`, `tar`, `sudo` 필수.
- AWS CLI 인증이 설정되어 있어야 클러스터 연결이 가능합니다.
- `.bashrc` 수정 후 새 터미널을 열어야 PATH 변경이 반영됩니다.

---

## 🧠 트러블슈팅

| 문제 | 원인 | 해결 방법 |
|------|------|------------|
| `kubectl: command not found` | PATH 미적용 | 터미널 재시작 또는 `source ~/.bashrc` 실행 |
| `kubectl krew version` 경고 | PATH 순서 문제 | `.bashrc` 내에서 `KREW_ROOT` 선언을 PATH보다 위로 이동 |
| `aws sts get-caller-identity` 실패 | AWS 인증 미설정 | `aws configure` 실행 |

---

## 👤 작성자

**Author:** [@johyobin](https://github.com/johyobin)  
**Version:** 1.0  
**License:** MIT  

---

> 💡 이 스크립트는 프로덕션 수준의 에러 핸들링(`trap`), 로그 관리, 환경 복구 기능을 포함하고 있습니다.  
> 리눅스 환경 초기 세팅 및 EKS 툴체인 배포 자동화에 유용하게 사용할 수 있습니다.
