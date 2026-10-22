-- ════════════════════════════════════════════════════════════
-- 럭키스타 — 검토결과 반영용 DB 변경 (한 번만 실행, 여러 번 실행해도 안전)
-- Supabase → SQL Editor 에 전체 붙여넣고 Run
-- ════════════════════════════════════════════════════════════

-- 1) 견적 부가 정보 (현장정보·실주·결제 상세·견적 조건·재고 상태·좌표·휴지통 등, JSON)
ALTER TABLE public.estimates ADD COLUMN IF NOT EXISTS meta TEXT DEFAULT '{}';
-- 2) 발송 이력 (가견적·본견적을 보낸 시점의 품목·금액, JSON 배열)
ALTER TABLE public.estimates ADD COLUMN IF NOT EXISTS send_history TEXT DEFAULT '[]';

-- 3) 견적번호 중복 방지 (이미 중복된 번호가 있으면 만들지 않고 알려줌)
DO $$
DECLARE dup text;
BEGIN
  SELECT string_agg(est_no, ', ') INTO dup FROM (
    SELECT est_no FROM public.estimates WHERE est_no IS NOT NULL AND est_no <> '' GROUP BY est_no HAVING count(*) > 1) d;
  IF dup IS NULL THEN
    CREATE UNIQUE INDEX IF NOT EXISTS estimates_est_no_unique ON public.estimates (est_no) WHERE est_no IS NOT NULL AND est_no <> '';
  ELSE
    RAISE NOTICE '중복된 견적번호가 있어 중복 방지를 만들지 않았습니다: %', dup;
  END IF;
END $$;

-- 4) 재고 입출고 기록 (언제·어느 견적·어떤 자재·몇 개)
CREATE TABLE IF NOT EXISTS public.stock_ledger (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  material_id UUID,
  material_name TEXT,
  estimate_id UUID,
  qty_change NUMERIC NOT NULL,          -- +입고/복구, -차감
  stock_after NUMERIC,
  reason TEXT,                          -- '설치 차감' / '차감 되돌리기' / '직접 수정' / '입고'
  memo TEXT,
  created_by TEXT DEFAULT (auth.jwt()->>'email')
);
ALTER TABLE public.stock_ledger ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS staff_all ON public.stock_ledger;
CREATE POLICY staff_all ON public.stock_ledger FOR ALL TO authenticated USING (public.is_staff()) WITH CHECK (public.is_staff());

-- 5) 재고 증감을 DB가 한 번에 처리 (두 사람이 동시에 해도 숫자가 틀리지 않음)
CREATE OR REPLACE FUNCTION public.adjust_stock(p_material UUID, p_delta NUMERIC, p_estimate UUID, p_reason TEXT, p_memo TEXT DEFAULT NULL)
RETURNS NUMERIC
LANGUAGE plpgsql SECURITY INVOKER
SET search_path = public
AS $$
DECLARE v_after NUMERIC; v_name TEXT;
BEGIN
  IF NOT public.is_staff() THEN RAISE EXCEPTION '권한이 없습니다'; END IF;
  UPDATE public.materials SET stock_qty = GREATEST(0, COALESCE(stock_qty,0) + p_delta)
   WHERE id = p_material RETURNING stock_qty, name INTO v_after, v_name;
  IF NOT FOUND THEN RAISE EXCEPTION '자재를 찾을 수 없습니다'; END IF;
  INSERT INTO public.stock_ledger(material_id, material_name, estimate_id, qty_change, stock_after, reason, memo)
  VALUES (p_material, v_name, p_estimate, p_delta, v_after, p_reason, p_memo);
  RETURN v_after;
END $$;
REVOKE ALL ON FUNCTION public.adjust_stock(UUID, NUMERIC, UUID, TEXT, TEXT) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.adjust_stock(UUID, NUMERIC, UUID, TEXT, TEXT) TO authenticated;

-- 6) 고객용 웹 견적서 링크 (?q=고유코드): 링크를 가진 사람만 그 견적 1건을 볼 수 있음
--    품목·금액·시공비·결제조건·포트폴리오 연결만 넘기고, 내부 메모·결제 내역·실측 정보 등은 넘기지 않음
CREATE OR REPLACE FUNCTION public.get_public_estimate(p_token TEXT)
RETURNS JSON
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = public
AS $$
DECLARE e RECORD; m JSONB; r JSON;
BEGIN
  IF p_token IS NULL OR p_token !~ '^[A-Za-z0-9]{20,}$' THEN RETURN NULL; END IF;
  SELECT * INTO e FROM public.estimates WHERE meta LIKE '%"shareToken":"' || p_token || '"%' LIMIT 1;
  IF NOT FOUND THEN RETURN NULL; END IF;
  BEGIN m := e.meta::jsonb; EXCEPTION WHEN others THEN m := '{}'::jsonb; END;
  IF coalesce(m->>'shareToken','') <> p_token OR m ? 'deletedAt' THEN RETURN NULL; END IF;
  SELECT json_build_object(
    'est_no', e.est_no, 'client_name', e.client_name, 'client_manager', e.client_manager, 'manager_phone', e.manager_phone,
    'created_at', e.created_at, 'status_dates', e.status_dates,
    'costs', m->'costs', 'terms', m->'terms',
    'cats', (SELECT coalesce(json_agg(json_build_object('id', c.id, 'name', c.name) ORDER BY c.display_order), '[]'::json)
             FROM public.est_cats c WHERE c.estimate_id = e.id),
    'items', (SELECT coalesce(json_agg(json_build_object(
                'cat_id', i.cat_id, 'name', i.name, 'specification', i.specification, 'quantity', i.quantity,
                'unit_price', i.unit_price, 'total_amount', i.total_amount, 'image_url', i.image_url,
                'portfolio_ids', (SELECT p.portfolio_ids FROM public.products p
                                  WHERE p.name = i.name AND coalesce(p.portfolio_ids,'[]') <> '[]' LIMIT 1)
              ) ORDER BY c2.display_order, i.display_order), '[]'::json)
              FROM public.est_items i JOIN public.est_cats c2 ON c2.id = i.cat_id WHERE c2.estimate_id = e.id),
    'settings', (SELECT value FROM public.app_settings WHERE key = 'estimate')
  ) INTO r;
  RETURN r;
END $$;
REVOKE ALL ON FUNCTION public.get_public_estimate(TEXT) FROM public;
GRANT EXECUTE ON FUNCTION public.get_public_estimate(TEXT) TO anon, authenticated;

-- 확인: 아래 결과에 meta, send_history 가 보이고 stock_ledger 가 rls_on=true 면 성공
SELECT column_name FROM information_schema.columns WHERE table_schema='public' AND table_name='estimates' AND column_name IN ('meta','send_history')
UNION ALL
SELECT 'stock_ledger rls_on=' || relrowsecurity FROM pg_class WHERE relname='stock_ledger';
