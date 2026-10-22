-- 사이트에서 쓰지 않는 옛 표 4개도 직원만 접근하도록 잠금 (rls_apply.sql 실행 후 추가 실행)
DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['categories','items','outsourcing_categories','outsourcing_items']
  LOOP
    IF to_regclass('public.'||t) IS NOT NULL THEN
      EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY', t);
      EXECUTE format('DROP POLICY IF EXISTS staff_all ON public.%I', t);
      EXECUTE format('CREATE POLICY staff_all ON public.%I FOR ALL TO authenticated USING (public.is_staff()) WITH CHECK (public.is_staff())', t);
    END IF;
  END LOOP;
END $$;

SELECT c.relname AS 표, c.relrowsecurity AS rls_on
FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
WHERE n.nspname='public' AND c.relkind='r' AND c.relname IN ('categories','items','outsourcing_categories','outsourcing_items');
