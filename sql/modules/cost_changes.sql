/* ============================================
   SUPPLIER COST AND STANDARD COST CHANGES  (module: cost_changes)
   Based on: CostChangeAudit, Standard_Cost_Changed_By_Purchasing
   One row per item and cost type changed in the last @AuditDays:
     cost          = supplier cost on inventory_supplier (replacement cost)
     standard_cost = standard cost on inv_loc (same change is usually
                     made at many locations, so it's collapsed per item)
   Cost before the first change, after the last change, edit count,
   locations touched, and who made the last change. Moving average cost is
   left out because the system updates it on every receipt.
   ============================================ */
SET NOCOUNT ON;
DECLARE @CompanyId INT = 1;
DECLARE @AuditDays INT = 90;

;WITH a AS (
    SELECT at.inv_mast_uid, at.column_changed, at.key2_value,
           TRY_CAST(at.old_value AS DECIMAL(19,6)) AS old_cost,
           TRY_CAST(at.new_value AS DECIMAL(19,6)) AS new_cost,
           at.created_by, at.date_created,
           ROW_NUMBER() OVER (PARTITION BY at.inv_mast_uid, at.column_changed ORDER BY at.date_created ASC,  at.audit_trail_uid ASC)  AS rn_first,
           ROW_NUMBER() OVER (PARTITION BY at.inv_mast_uid, at.column_changed ORDER BY at.date_created DESC, at.audit_trail_uid DESC) AS rn_last
    FROM dbo.audit_trail at
    WHERE at.date_created >= DATEADD(DAY, -@AuditDays, GETDATE())
      AND ((at.table_changed = 'inventory_supplier' AND at.column_changed = 'cost')
        OR (at.table_changed = 'inv_loc'            AND at.column_changed = 'standard_cost' AND at.key2_value IN (SELECT CAST(CAST(location_id AS BIGINT) AS VARCHAR(20)) FROM dbo.location WHERE company_id = @CompanyId)))
      AND EXISTS (SELECT 1 FROM dbo.inv_loc il WHERE il.inv_mast_uid = at.inv_mast_uid AND il.company_id = @CompanyId)
)
SELECT
    im.item_id,
    a.column_changed                                            AS cost_type,
    CAST(MAX(CASE WHEN rn_first = 1 THEN old_cost END) AS DECIMAL(19,4)) AS cost_before,
    CAST(MAX(CASE WHEN rn_last  = 1 THEN new_cost END) AS DECIMAL(19,4)) AS cost_after,
    -- per stocking unit, as in CostChangeAudit: supplier cost is per purchase pricing unit,
    -- standard cost per sales pricing unit
    CAST(MAX(CASE WHEN rn_first = 1 THEN old_cost END)
         / NULLIF(CASE a.column_changed WHEN 'cost' THEN MAX(im.purchase_pricing_unit_size) ELSE MAX(im.sales_pricing_unit_size) END, 0) AS DECIMAL(19,6)) AS unit_before,
    CAST(MAX(CASE WHEN rn_last  = 1 THEN new_cost END)
         / NULLIF(CASE a.column_changed WHEN 'cost' THEN MAX(im.purchase_pricing_unit_size) ELSE MAX(im.sales_pricing_unit_size) END, 0) AS DECIMAL(19,6)) AS unit_after,
    COUNT(*)                                                    AS edits,
    COUNT(DISTINCT a.key2_value)                                AS locations,
    MAX(CASE WHEN rn_last = 1 THEN a.created_by END)            AS changed_by,
    CAST(MAX(a.date_created) AS DATE)                           AS last_changed
FROM a
JOIN dbo.inv_mast im ON im.inv_mast_uid = a.inv_mast_uid
GROUP BY im.item_id, a.column_changed;
