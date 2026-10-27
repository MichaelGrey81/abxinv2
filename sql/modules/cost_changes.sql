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
   po_median_unit is the item's median PO price per unit over the last year,
   to compare the new cost with what we have actually been paying.
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
, po12 AS (   -- PO prices for these items over the last year, per single unit
    SELECT DISTINCT pl.inv_mast_uid,
           PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY pl.unit_price / NULLIF(pl.pricing_unit_size, 0)) OVER (PARTITION BY pl.inv_mast_uid) AS po_median_unit,
           COUNT(*) OVER (PARTITION BY pl.inv_mast_uid) AS po_lines_12m
    FROM dbo.po_line pl
    JOIN dbo.po_hdr ph ON ph.po_no = pl.po_no
    WHERE ph.company_no = @CompanyId AND ph.order_date >= DATEADD(YEAR, -1, GETDATE())
      AND ph.delete_flag = 'N' AND pl.delete_flag = 'N' AND pl.cancel_flag = 'N'
      AND pl.qty_ordered > 0 AND pl.unit_price > 0 AND pl.pricing_unit_size > 0
      AND pl.inv_mast_uid IN (SELECT inv_mast_uid FROM a)
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
    MAX(CASE WHEN rn_last = 1 THEN COALESCE(NULLIF(LTRIM(RTRIM(ISNULL(c.first_name, '') + ' ' + ISNULL(c.last_name, ''))), ''), u.name) END) AS changed_by_name,
    CAST(MAX(a.date_created) AS DATE)                           AS last_changed,
    CAST(MAX(po12.po_median_unit) AS DECIMAL(19,6))             AS po_median_unit,
    MAX(po12.po_lines_12m)                                      AS po_lines_12m
FROM a
JOIN dbo.inv_mast im ON im.inv_mast_uid = a.inv_mast_uid
LEFT JOIN dbo.users u    ON u.id = a.created_by
LEFT JOIN dbo.contacts c ON c.id = u.contact_id
LEFT JOIN po12 ON po12.inv_mast_uid = a.inv_mast_uid
GROUP BY im.item_id, a.column_changed;
