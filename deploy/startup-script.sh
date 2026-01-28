#!/bin/bash
# VM 시작 시 자동으로 실행되는 스크립트

set -e

APP_DIR="/opt/morning-briefing"
REPO_URL="https://github.com/seanjeon20-boop/morning-briefing-bot.git"

# 시스템 업데이트
apt-get update
apt-get upgrade -y

# 필수 패키지 설치
apt-get install -y \
  git \
  curl \
  libssl-dev \
  libreadline-dev \
  zlib1g-dev \
  autoconf \
  bison \
  build-essential \
  libyaml-dev \
  libncurses5-dev \
  libffi-dev \
  libgdbm-dev \
  libsqlite3-dev \
  nodejs \
  npm

# rbenv 설치
if [ ! -d "/root/.rbenv" ]; then
  git clone https://github.com/rbenv/rbenv.git /root/.rbenv
  echo 'export PATH="/root/.rbenv/bin:$PATH"' >> /root/.bashrc
  echo 'eval "$(rbenv init -)"' >> /root/.bashrc
  git clone https://github.com/rbenv/ruby-build.git /root/.rbenv/plugins/ruby-build
fi

export PATH="/root/.rbenv/bin:$PATH"
eval "$(rbenv init -)"

# Ruby 3.4 설치
if ! rbenv versions | grep -q "3.4"; then
  rbenv install 3.4.1
  rbenv global 3.4.1
fi

# Bundler 설치
gem install bundler

# 앱 디렉토리 생성
mkdir -p $APP_DIR

echo "VM 초기 설정 완료!"
echo "다음 단계: 코드 배포 및 환경변수 설정"
