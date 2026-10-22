-- ════════════════════════════════════════════════════════════
-- 럭키스타 관리 시스템 — 데이터 보안(RLS) 적용
-- Supabase 대시보드 → SQL Editor 에 전체를 붙여넣고 Run (한 번만 실행)
-- 규칙: "승인된 직원(사용자 관리에 등록된 이메일) + 관리자"만 데이터를 읽고 쓸 수 있음
--   · 예외 1) 포트폴리오: 고객용 공개 링크(QR)를 위해 누구나 '보기'만 가능
--   · 예외 2) 승인 여부 확인·첫 로그인 프로필 생성: 로그인한 본인 것만
-- 문제가 생기면 rls_rollback.sql 을 실행하면 원래대로 돌아감
-- ════════════════════════════════════════════════════════════

-- 1) 직원 여부 판정 함수 (관리자 이메일 또는 approved_users 에 있는 이메일)
CREATE OR REPLACE FUNCTION public.is_staff()
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public
AS $$
  SELECT lower(coalesce(auth.jwt()->>'email','')) = 'kyuill75@gmail.com'
      OR EXISTS (SELECT 1 FROM public.approved_users a
                 WHERE lower(a.email) = lower(coalesce(auth.jwt()->>'email','')));
$$;
REVOKE ALL ON FUNCTION public.is_staff() FROM public;
GRANT EXECUTE ON FUNCTION public.is_staff() TO anon, authenticated;

-- 2) 업무 데이터 표: 직원만 읽기·쓰기
DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['materials','suppliers','material_categories','product_categories','tool_categories',
                           'products','product_materials','tools','portfolios','estimates','est_cats','est_items','app_settings',
                           -- 사이트에서 쓰지 않는 옛 표 (열려 있던 것을 함께 잠금)
                           'categories','items','outsourcing_categories','outsourcing_items']
  LOOP
    IF to_regclass('public.'||t) IS NOT NULL THEN
      EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY', t);
      EXECUTE format('DROP POLICY IF EXISTS staff_all ON public.%I', t);
      EXECUTE format('CREATE POLICY staff_all ON public.%I FOR ALL TO authenticated USING (public.is_staff()) WITH CHECK (public.is_staff())', t);
    END IF;
  END LOOP;
END $$;

-- 3) 포트폴리오: 고객 공개 링크(?pf=)용으로 누구나 보기만 가능
DROP POLICY IF EXISTS public_read ON public.portfolios;
CREATE POLICY public_read ON public.portfolios FOR SELECT TO anon, authenticated USING (true);

-- 4) 승인 목록: 본인 승인 여부 확인은 누구나(로그인한 본인 것만), 승인·취소는 관리자만
ALTER TABLE public.approved_users ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS read_own_or_staff ON public.approved_users;
CREATE POLICY read_own_or_staff ON public.approved_users FOR SELECT TO authenticated
  USING (lower(email) = lower(coalesce(auth.jwt()->>'email','')) OR public.is_staff());
DROP POLICY IF EXISTS admin_write ON public.approved_users;
CREATE POLICY admin_write ON public.approved_users FOR ALL TO authenticated
  USING (lower(coalesce(auth.jwt()->>'email','')) = 'kyuill75@gmail.com')
  WITH CHECK (lower(coalesce(auth.jwt()->>'email','')) = 'kyuill75@gmail.com');

-- 5) 직원 프로필: 직원끼리는 서로 보기(담당자 선택), 본인 것만 만들기·고치기
ALTER TABLE public.user_profiles ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS profiles_read ON public.user_profiles;
CREATE POLICY profiles_read ON public.user_profiles FOR SELECT TO authenticated
  USING (public.is_staff() OR lower(email) = lower(coalesce(auth.jwt()->>'email','')));
DROP POLICY IF EXISTS profiles_insert_own ON public.user_profiles;
CREATE POLICY profiles_insert_own ON public.user_profiles FOR INSERT TO authenticated
  WITH CHECK (lower(email) = lower(coalesce(auth.jwt()->>'email','')));
DROP POLICY IF EXISTS profiles_update_own ON public.user_profiles;
CREATE POLICY profiles_update_own ON public.user_profiles FOR UPDATE TO authenticated
  USING (lower(email) = lower(coalesce(auth.jwt()->>'email','')) OR lower(coalesce(auth.jwt()->>'email','')) = 'kyuill75@gmail.com')
  WITH CHECK (lower(email) = lower(coalesce(auth.jwt()->>'email','')) OR lower(coalesce(auth.jwt()->>'email','')) = 'kyuill75@gmail.com');
DROP POLICY IF EXISTS profiles_admin_delete ON public.user_profiles;
CREATE POLICY profiles_admin_delete ON public.user_profiles FOR DELETE TO authenticated
  USING (lower(coalesce(auth.jwt()->>'email','')) = 'kyuill75@gmail.com');

-- 6) 사진·파일 저장소(lucky-star 버킷)
--    사진 주소(공개 URL)로 보는 것은 그대로 가능 · 목록 조회·업로드·삭제는 직원만
DROP POLICY IF EXISTS "allow_upload" ON storage.objects;
DROP POLICY IF EXISTS "allow_view"   ON storage.objects;
DROP POLICY IF EXISTS "allow_delete" ON storage.objects;
DROP POLICY IF EXISTS ls_staff_select ON storage.objects;
DROP POLICY IF EXISTS ls_staff_insert ON storage.objects;
DROP POLICY IF EXISTS ls_staff_update ON storage.objects;
DROP POLICY IF EXISTS ls_staff_delete ON storage.objects;
CREATE POLICY ls_staff_select ON storage.objects FOR SELECT TO authenticated USING (bucket_id = 'lucky-star' AND public.is_staff());
CREATE POLICY ls_staff_insert ON storage.objects FOR INSERT TO authenticated WITH CHECK (bucket_id = 'lucky-star' AND public.is_staff());
CREATE POLICY ls_staff_update ON storage.objects FOR UPDATE TO authenticated USING (bucket_id = 'lucky-star' AND public.is_staff()) WITH CHECK (bucket_id = 'lucky-star' AND public.is_staff());
CREATE POLICY ls_staff_delete ON storage.objects FOR DELETE TO authenticated USING (bucket_id = 'lucky-star' AND public.is_staff());

-- 7) 적용 결과 확인 (아래 표에 모든 표가 rls_on = true 로 나오면 성공)
SELECT c.relname AS 표, c.relrowsecurity AS rls_on,
       (SELECT count(*) FROM pg_policies p WHERE p.schemaname='public' AND p.tablename=c.relname) AS 규칙수
FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
WHERE n.nspname='public' AND c.relkind='r'
ORDER BY 1;
