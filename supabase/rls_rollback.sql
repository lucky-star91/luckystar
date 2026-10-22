-- ════════════════════════════════════════════════════════════
-- 럭키스타 관리 시스템 — RLS 되돌리기 (rls_apply.sql 실행 전 상태로)
-- 사이트에서 데이터가 안 보이거나 저장이 안 되면 SQL Editor 에서 전체 실행
-- ════════════════════════════════════════════════════════════

DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['materials','suppliers','material_categories','product_categories','tool_categories',
                           'products','product_materials','tools','portfolios','estimates','est_cats','est_items','app_settings',
                           'approved_users','user_profiles',
                           'categories','items','outsourcing_categories','outsourcing_items']
  LOOP
    IF to_regclass('public.'||t) IS NOT NULL THEN
      EXECUTE format('ALTER TABLE public.%I DISABLE ROW LEVEL SECURITY', t);
      EXECUTE format('DROP POLICY IF EXISTS staff_all ON public.%I', t);
    END IF;
  END LOOP;
END $$;

DROP POLICY IF EXISTS public_read           ON public.portfolios;
DROP POLICY IF EXISTS read_own_or_staff     ON public.approved_users;
DROP POLICY IF EXISTS admin_write           ON public.approved_users;
DROP POLICY IF EXISTS profiles_read         ON public.user_profiles;
DROP POLICY IF EXISTS profiles_insert_own   ON public.user_profiles;
DROP POLICY IF EXISTS profiles_update_own   ON public.user_profiles;
DROP POLICY IF EXISTS profiles_admin_delete ON public.user_profiles;

-- 저장소: 예전 규칙으로 복구 (로그인하면 업로드·삭제, 누구나 보기)
DROP POLICY IF EXISTS ls_staff_select ON storage.objects;
DROP POLICY IF EXISTS ls_staff_insert ON storage.objects;
DROP POLICY IF EXISTS ls_staff_update ON storage.objects;
DROP POLICY IF EXISTS ls_staff_delete ON storage.objects;
DROP POLICY IF EXISTS "allow_upload" ON storage.objects;
DROP POLICY IF EXISTS "allow_view"   ON storage.objects;
DROP POLICY IF EXISTS "allow_delete" ON storage.objects;
CREATE POLICY "allow_upload" ON storage.objects FOR INSERT TO authenticated WITH CHECK (bucket_id='lucky-star');
CREATE POLICY "allow_view"   ON storage.objects FOR SELECT TO public USING (bucket_id='lucky-star');
CREATE POLICY "allow_delete" ON storage.objects FOR DELETE TO authenticated USING (bucket_id='lucky-star');

DROP FUNCTION IF EXISTS public.is_staff();
