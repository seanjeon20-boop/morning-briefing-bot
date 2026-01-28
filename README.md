# Morning Briefing Bot

매일 아침 CNBC와 Yahoo Finance의 YouTube 영상을 수집하여 Gemini AI로 요약/분석 후 텔레그램으로 전송하는 모닝 브리핑 봇입니다.

## 기능

- **YouTube 비디오 수집**: CNBC, Yahoo Finance 채널에서 한국시각 00:00~07:00 사이 업로드된 영상 수집
- **자막 추출**: YouTube 자막을 자동으로 추출하여 분석에 활용
- **시장 데이터**: S&P 500, NASDAQ, DOW, VIX 등 주요 지수 및 섹터별 ETF 등락률 수집
- **AI 분석 (Gemini)**:
  - 3줄 요약
  - 투자 관점 의견
  - 6하원칙 기반 상세 분석
  - 시장 상황 연계 분석
- **텔레그램 봇**: 인라인 버튼으로 상세 분석 조회 가능

## 설정

### 1. 환경 변수 설정

`.env.example`을 `.env`로 복사하고 API 키를 입력하세요:

```bash
cp .env.example .env
```

필요한 API 키:

| 환경 변수 | 설명 | 발급처 |
|-----------|------|--------|
| `YOUTUBE_API_KEY` | YouTube Data API v3 키 | [Google Cloud Console](https://console.cloud.google.com/apis/credentials) |
| `GEMINI_API_KEY` | Google Gemini API 키 | [Google AI Studio](https://aistudio.google.com/app/apikey) |
| `TELEGRAM_BOT_TOKEN` | 텔레그램 봇 토큰 | [@BotFather](https://t.me/BotFather) |
| `TELEGRAM_CHAT_ID` | 브리핑 받을 채팅 ID | [@userinfobot](https://t.me/userinfobot) |

### 2. 의존성 설치

```bash
bundle install
```

### 3. 데이터베이스 설정

```bash
bin/rails db:prepare
```

## 사용법

### 로컬에서 실행

```bash
# 테스트 메시지 전송
bin/rails telegram:test

# 수동으로 브리핑 생성
bin/rails telegram:briefing

# 특정 날짜 브리핑 생성
bin/rails telegram:briefing_for[2026-01-28]

# 텔레그램 봇 폴링 시작 (상세 분석 버튼 처리용)
bin/rails telegram:bot

# 백그라운드 작업 처리 (스케줄러)
bin/rails solid_queue:start
```

### 자동 실행 (스케줄)

`config/recurring.yml`에 설정된 대로 매일 UTC 22:00 (KST 07:00)에 자동으로 브리핑이 생성됩니다.

## 배포 (Railway)

### 1. Railway 프로젝트 생성

```bash
# Railway CLI 설치
npm install -g @railway/cli

# 로그인 및 프로젝트 생성
railway login
railway init
```

### 2. 환경 변수 설정

Railway 대시보드에서 다음 환경 변수를 설정하세요:

```
YOUTUBE_API_KEY=your_key
GEMINI_API_KEY=your_key
TELEGRAM_BOT_TOKEN=your_token
TELEGRAM_CHAT_ID=your_chat_id
RAILS_ENV=production
SECRET_KEY_BASE=your_secret
```

### 3. 배포

```bash
railway up
```

### 4. 프로세스 설정

Railway에서 3개의 서비스를 실행해야 합니다:

1. **web**: Rails 웹 서버 (기본)
2. **worker**: Solid Queue 백그라운드 작업 처리
3. **telegram**: 텔레그램 봇 폴링

## 아키텍처

```
app/
├── services/
│   ├── youtube_crawler.rb        # YouTube 비디오 수집
│   ├── transcript_fetcher.rb     # 자막 추출
│   ├── market_data_fetcher.rb    # 시장 데이터 수집
│   ├── gemini_analyzer.rb        # AI 요약/분석
│   └── telegram_bot_service.rb   # 텔레그램 봇
├── jobs/
│   └── morning_briefing_job.rb   # 브리핑 작업
```

## 브리핑 예시

```
📊 2026.01.28 모닝 브리핑

[시장 현황]
🟢 S&P 500: 5,234.50 (+0.82%)
🟢 NASDAQ: 16,432.10 (+1.23%)
🟢 DOW: 39,123.45 (+0.45%)
🔴 VIX: 14.23 (-2.34%)

🔥 핫 섹터: Technology, Communication Services, Consumer Discretionary
❄️ 부진 섹터: Utilities, Real Estate, Consumer Staples

━━━━━━━━━━━━━━━━━━
📈 1. Fed Chair Powell speaks on monetary policy
📺 CNBC | ⏱ 12:34

1. 파월 의장이 금리 인하 가능성을 시사했습니다.
2. 인플레이션이 목표치에 근접하고 있다고 평가했습니다.
3. 노동 시장은 여전히 강세를 유지하고 있습니다.

💡 투자 포인트
금리에 민감한 성장주와 기술주에 긍정적인 신호입니다.

🏷 관련: Technology, Financials

[📖 상세 분석 보기] [🎬 영상 보기]
```

## 라이센스

MIT
