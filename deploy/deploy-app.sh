#!/bin/bash
# VM에서 실행: 앱 배포 스크립트
set -e

APP_DIR="/opt/morning-briefing"
REPO_URL="https://github.com/seanjeon20-boop/morning-briefing-bot.git"

export PATH="/root/.rbenv/bin:$PATH"
eval "$(rbenv init -)"

echo "🚀 Morning Briefing Bot 배포 시작"

# 1. 코드 클론 또는 업데이트
if [ -d "$APP_DIR/.git" ]; then
  echo "📥 코드 업데이트 중..."
  cd $APP_DIR
  git pull origin main
else
  echo "📥 코드 클론 중..."
  rm -rf $APP_DIR
  git clone $REPO_URL $APP_DIR
  cd $APP_DIR
fi

# 2. 의존성 설치
echo "📦 의존성 설치 중..."
bundle install --deployment --without development test

# 3. 데이터베이스 설정
echo "🗄️ 데이터베이스 설정 중..."
RAILS_ENV=production bundle exec rails db:prepare

# 4. 환경변수 파일 확인
if [ ! -f "$APP_DIR/.env" ]; then
  echo ""
  echo "⚠️  환경변수 파일이 없습니다!"
  echo "다음 명령어로 환경변수를 설정하세요:"
  echo ""
  echo "sudo nano /opt/morning-briefing/.env"
  echo ""
  echo "필요한 환경변수:"
  echo "  YOUTUBE_API_KEY=your_key"
  echo "  GEMINI_API_KEY=your_key"
  echo "  TELEGRAM_BOT_TOKEN=your_token"
  echo "  TELEGRAM_CHAT_ID=your_chat_id"
  echo "  SECRET_KEY_BASE=$(bundle exec rails secret)"
  echo ""
fi

echo "✅ 배포 완료!"
echo ""
echo "다음 단계:"
echo "1. 환경변수 설정: sudo nano /opt/morning-briefing/.env"
echo "2. systemd 서비스 설정:"
echo "   sudo cp /opt/morning-briefing/deploy/systemd/* /etc/systemd/system/"
echo "   sudo systemctl daemon-reload"
echo "   sudo systemctl enable morning-briefing morning-briefing-bot"
echo "   sudo systemctl start morning-briefing morning-briefing-bot"
