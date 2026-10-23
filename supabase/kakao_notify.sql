-- ★ 카카오톡 직원 알림 (서버 함수 supabase/functions/kakao 가 사용)
-- kakao_sender : 알림을 보내는 카카오 계정(사장님)의 로그인 토큰 — 화면(직원)에서는 읽을 수 없고 서버 함수만 읽음
-- kakao_members: '알림 받기 동의'를 한 직원 기록 (화면에서 동의 여부 확인용)
-- 받는 사람 선택·켜기/끄기는 app_settings key='kakao_notify' 에 JSON 으로 저장 (기존 staff_all 규칙 그대로)
-- 되돌리기: DROP TABLE IF EXISTS kakao_sender; DROP TABLE IF EXISTS kakao_members;

CREATE TABLE IF NOT EXISTS kakao_sender (
  id INT PRIMARY KEY DEFAULT 1 CHECK (id = 1),
  kakao_id BIGINT,
  nickname TEXT,
  access_token TEXT,
  refresh_token TEXT,
  expires_at TIMESTAMPTZ,
  refresh_expires_at TIMESTAMPTZ,
  connected_by TEXT,
  updated_at TIMESTAMPTZ DEFAULT NOW()
);
-- RLS 켜고 규칙은 만들지 않음 → 로그인한 직원도 토큰을 못 읽음 (서버 함수의 service role 만 접근)
ALTER TABLE kakao_sender ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS kakao_members (
  kakao_id BIGINT PRIMARY KEY,
  nickname TEXT,
  user_email TEXT,
  updated_at TIMESTAMPTZ DEFAULT NOW()
);
ALTER TABLE kakao_members ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS staff_read ON kakao_members;
CREATE POLICY staff_read ON kakao_members FOR SELECT TO authenticated USING (public.is_staff());
