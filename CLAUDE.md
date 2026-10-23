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
- estimates.meta (JSON): lost(실주) · pay(입금 내역) · costs(설치·운반·철거비) · terms(결제 조건) · site(현장정보) · stock(재고 차감 상태) · shareToken(고객용 링크) · geo(좌표) · deletedAt(휴지통). estimates.send_history: 견적 이력. 일부 항목만 바로 저장할 때는 `persistMetaKey`
- 재고 증감은 반드시 `adjustStock` (DB 함수 adjust_stock → stock_ledger 기록). 고객용 웹 견적서 `?q=토큰` → DB 함수 get_public_estimate. SQL은 supabase/batch2_columns.sql
- 견적번호: 날짜+그날 순번 (`nextEstNo`), 저장할 때 부여
- 자재분류 2단계: material_categories.parent_id (없음=상위, 있음=하위). 자재는 하위분류에 등록, 예전 자재는 상위분류에 남아 '하위분류 미지정'. 사이드바·공급사·상품은 상위분류만(`topMatCats`), 자재가 어느 상위분류인지는 `matTopId`
- 노무비(labor_cost)는 사용하지 않음 — DB 컬럼만 남아 있고 화면·인쇄·엑셀에서는 제외
- RLS 적용됨(2026-10-22): `public.is_staff()`(관리자 이메일 또는 approved_users) 인 로그인 사용자만 접근. 예외: portfolios 누구나 보기, approved_users/user_profiles 본인 행. SQL은 `supabase/` 폴더 (rls_apply·rls_apply_old_tables·rls_rollback). 새 표를 만들면 같은 staff_all 규칙을 꼭 추가할 것
- 카카오톡 할 일 알림: 서버 함수 `supabase/functions/kakao` (Supabase Edge Function, 비밀값 KAKAO_CLIENT_SECRET·CRON_SECRET) + 환경설정 `KakaoNotify`. 보내는 계정 토큰은 `kakao_sender`(규칙 없는 RLS — 서버 함수만 읽음), 받는 직원·켜기는 app_settings key='kakao_notify'. 할 일 계산 규칙(`todoLists`)을 바꾸면 서버 함수의 buildDigest 도 같이 고칠 것. 서버 함수 수정 후에는 다시 배포해야 함. 메시지 속 링크 도메인은 카카오 개발자 앱 '제품 링크 관리 → 웹 도메인'에 등록돼 있어야 함(없으면 링크가 조용히 빠짐). 카톡 내부 브라우저는 index.html 상단 스크립트가 일반 브라우저로 넘김(구글 로그인 차단 때문)
- 배포: GitHub `main` 브랜치 → Vercel

## 작업 규칙
- 사용자는 한국어로 소통. 화면 문구도 한국어
- `index.html`은 4,000줄 이상 — 필요한 부분만 Edit로 수정, 통째로 다시 쓰지 말 것
- 기존 코드 스타일(짧은 변수명, 한 줄 JSX, 인라인 style) 유지
- 로컬 확인: `py -m http.server 8080` 후 http://localhost:8080
- 커밋/푸시는 사용자 확인 후에만 (푸시하면 실제 사이트에 바로 반영됨)
