-- ★ 자재 하위분류 (2026-10-23 적용됨)
-- material_categories.parent_id 가 비어 있으면 상위분류, 있으면 그 상위분류의 하위분류
-- 자재(materials.category_id)는 하위분류를 가리킴 (예전 자재는 상위분류를 가리킨 채 '하위분류 미지정'으로 표시)
ALTER TABLE material_categories ADD COLUMN IF NOT EXISTS parent_id UUID REFERENCES material_categories(id) ON DELETE CASCADE;
CREATE INDEX IF NOT EXISTS material_categories_parent_idx ON material_categories(parent_id);
-- 되돌리기: DELETE FROM material_categories WHERE parent_id IS NOT NULL; ALTER TABLE material_categories DROP COLUMN parent_id;
