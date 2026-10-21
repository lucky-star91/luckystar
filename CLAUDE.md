# 럭키스타 캠핑카라반 관리 시스템

가구 견적·자재·제품·일정·포트폴리오 관리 웹앱.

## 구조
- `index.html` 한 파일에 전부 들어 있음 (CSS + React 컴포넌트 + App)
  - React 18 / Supabase JS / SheetJS / qrcodejs 를 CDN으로 로드
  - `<script type="text/babel">` — 브라우저에서 Babel로 JSX 변환 (빌드 과정 없음)
- `vercel.json` — 정적 배포, 모든 경로를 index.html로 라우팅
- `.github/workflows/supabase-keepalive.yml` — 하루 2번 Supabase 핑(비활성화 방지)
- `.github/index.html` — 예전 버전 사본으로 보임 (사용 안 함)

## 백엔드
- Supabase (DB, 구글 로그인, 파일 저장소). 접속 URL/키는 첫 실행 시 화면에서 입력 → `localStorage.supabase_config`
- 환경설정(상호·견적서 공통내용): `app_settings` 테이블, key='estimate' 행에 JSON 저장 (`loadSettings`, `SQL_SETTINGS`)
- 진행 단계는 저장값이 아니라 `getStage`로 판정 (status_dates·status_checked·deposit_amount·balance_paid). 보류는 `isOnHold`로 계산(환경설정 holdDays). 옛 '견적예정' 키는 `normStatusObj`로 '본견적발송'으로 읽음
- 방문 예약 추천(`VisitPlanner`): 카카오 지도 JS SDK로 주소→좌표(`geocode`, localStorage 캐시), 직선거리로 같은 날 동선 묶기. 카카오 JS 키는 도메인 제한 공개 키(등록 도메인: localhost:8080, project-hv4qh.vercel.app)
- 노무비(labor_cost)는 사용하지 않음 — DB 컬럼만 남아 있고 화면·인쇄·엑셀에서는 제외
- ⚠️ 모든 표 RLS 꺼짐 (비로그인도 공개 키로 데이터 접근 가능) — 보안 작업 보류 중. 사용자가 "RLS"라고 입력하면 작업 계획(정책 SQL·되돌리기 SQL·점검 체크리스트, 포트폴리오 공개 링크와 Storage 예외)을 다시 안내할 것
- 배포: GitHub `main` 브랜치 → Vercel

## 작업 규칙
- 사용자는 한국어로 소통. 화면 문구도 한국어
- `index.html`은 4,000줄 이상 — 필요한 부분만 Edit로 수정, 통째로 다시 쓰지 말 것
- 기존 코드 스타일(짧은 변수명, 한 줄 JSX, 인라인 style) 유지
- 로컬 확인: `py -m http.server 8080` 후 http://localhost:8080
- 커밋/푸시는 사용자 확인 후에만 (푸시하면 실제 사이트에 바로 반영됨)
