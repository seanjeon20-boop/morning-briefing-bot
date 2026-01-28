#!/bin/bash
# Google Cloud Compute Engine 배포 스크립트
# 이 스크립트를 실행하면 자동으로 VM이 생성되고 앱이 배포됩니다.

set -e

PROJECT_ID="morning-financial-brief"
ZONE="asia-northeast3-a"  # 서울 리전
INSTANCE_NAME="morning-briefing-bot"

echo "🚀 Morning Briefing Bot - Google Cloud 배포"
echo "============================================"

# 1. 프로젝트 설정
echo "1. 프로젝트 설정 중..."
gcloud config set project $PROJECT_ID

# 2. 필요한 API 활성화
echo "2. API 활성화 중..."
gcloud services enable compute.googleapis.com

# 3. VM 인스턴스 생성 (e2-micro = 무료 티어)
echo "3. VM 인스턴스 생성 중..."
gcloud compute instances create $INSTANCE_NAME \
  --zone=$ZONE \
  --machine-type=e2-small \
  --image-family=ubuntu-2204-lts \
  --image-project=ubuntu-os-cloud \
  --boot-disk-size=20GB \
  --tags=http-server \
  --metadata-from-file startup-script=deploy/startup-script.sh

echo "4. VM 생성 완료! IP 주소 확인 중..."
gcloud compute instances describe $INSTANCE_NAME --zone=$ZONE --format='get(networkInterfaces[0].accessConfigs[0].natIP)'

echo ""
echo "✅ 배포 완료!"
echo ""
echo "다음 단계:"
echo "1. VM에 SSH 접속: gcloud compute ssh $INSTANCE_NAME --zone=$ZONE"
echo "2. 환경변수 설정: sudo nano /opt/morning-briefing/.env"
echo "3. 서비스 시작: sudo systemctl start morning-briefing"
