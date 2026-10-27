/* ============================================
   PURCHASING BY BRANCH AND WRITER  (module: branch_purchasing)
   Branch POs entered in the last @BuyerDays, one row per branch and PO
   buyer (requested-by contact). The dashboard splits each branch's
   purchasing between the corporate team (config corp_buyers) and branch
   staff, and sets it against the branch's performance.

   Stocked or not when bought: each PO line's item-location is rebuilt as
   of the moment the PO was entered from the inv_loc audit trail (the
   value before the first change after that moment, otherwise today's
   value). Stocked = stockable Y, max > 0, purchase class not NS, the same
   rule used everywhere else; an item-location added after the PO was
   entered counts as not stocked. Not-stocked lines are split three ways:
   tied to a customer order (oe_line_po) or a direct ship; not tied, but
   the branch had customer order lines for the item within @DemandDays
   before or after the PO; or neither (no customer demand seen).
   ============================================ */
SET NOCOUNT ON;
DECLARE @CompanyId INT = 1;
DECLARE @BuyerDays INT = 180;
DECLARE @Start DATE = DATEADD(DAY, -@BuyerDays, CAST(GETDATE() AS DATE));
DECLARE @Today DATE = CAST(GETDATE() AS DATE);
DECLARE @DemandDays INT = 30;

IF OBJECT_ID('tempdb..#pl') IS NOT NULL DROP TABLE #pl;
IF OBJECT_ID('tempdb..#au') IS NOT NULL DROP TABLE #au;

SELECT
    ph.location_id, pl.po_no, pl.line_no, pl.inv_mast_uid, ph.po_type,
    CASE WHEN ph.date_created < ph.order_date THEN ph.date_created ELSE ph.order_date END AS entered,
    COALESCE(NULLIF(LTRIM(RTRIM(ISNULL(c.first_name, '') + ' ' + ISNULL(c.last_name, ''))), ''), '(no requester)') AS buyer,
    CAST(pl.qty_ordered * pl.unit_price / NULLIF(pl.pricing_unit_size, 0) AS DECIMAL(19,2)) AS val,
    pl.qty_ordered, pl.qty_received, pl.received_date,
    CAST(COALESCE(pl.date_due, ph.expected_date, ph.date_due) AS DATE) AS due,
    il.stockable, il.inv_max, il.purchase_class,
    CASE WHEN il.stockable = 'Y' AND il.inv_max > 0 AND ISNULL(il.purchase_class, '') <> 'NS' THEN 1 ELSE 0 END AS stk_now,
    CASE WHEN EXISTS (SELECT 1 FROM dbo.oe_line_po x WHERE x.po_no = pl.po_no AND x.po_line_number = pl.line_no AND x.delete_flag = 'N') THEN 1 ELSE 0 END AS for_order
INTO #pl
FROM dbo.po_line pl
JOIN dbo.po_hdr ph       ON ph.po_no = pl.po_no
LEFT JOIN dbo.contacts c ON c.id = ph.requested_by
LEFT JOIN dbo.inv_loc il ON il.inv_mast_uid = pl.inv_mast_uid AND il.location_id = ph.location_id
WHERE ph.company_no = @CompanyId
  AND ph.location_id IN (10000,11000,11500,12000,20000,21000,30000,30100,31000,31500,40000,50000,70000,71000)
  AND ph.order_date >= @Start
  AND ph.delete_flag = 'N' AND pl.delete_flag = 'N' AND pl.cancel_flag = 'N'
  AND pl.qty_ordered > 0;

-- inv_loc audit rows since the earliest PO for those item-locations
SELECT at.inv_mast_uid, TRY_CAST(at.key2_value AS DECIMAL(19,0)) AS location_id, at.column_changed, at.old_value, at.date_created, at.audit_trail_uid
INTO #au
FROM dbo.audit_trail at
WHERE at.table_changed = 'inv_loc'
  AND at.column_changed IN ('stockable', 'inv_max', 'purchase_class', 'location_id')
  AND at.date_created >= DATEADD(DAY, -1, @Start)
  AND at.key2_value IN (SELECT DISTINCT CAST(CAST(location_id AS BIGINT) AS VARCHAR(20)) FROM #pl)
  AND EXISTS (SELECT 1 FROM #pl p WHERE p.inv_mast_uid = at.inv_mast_uid);
CREATE CLUSTERED INDEX ix_au ON #au (inv_mast_uid, location_id, column_changed, date_created);

;WITH t AS (
    SELECT p.*,
           COALESCE(s.old_value, p.stockable) AS stockable_then,
           COALESCE(TRY_CAST(m.old_value AS DECIMAL(19,4)), p.inv_max) AS max_then,
           COALESCE(k.old_value, p.purchase_class) AS class_then,
           CASE WHEN ad.date_created IS NOT NULL OR p.stockable IS NULL THEN 1 ELSE 0 END AS added_after
    FROM #pl p
    OUTER APPLY (SELECT TOP 1 a.old_value FROM #au a WHERE a.inv_mast_uid = p.inv_mast_uid AND a.location_id = p.location_id AND a.column_changed = 'stockable'      AND a.date_created > p.entered ORDER BY a.date_created, a.audit_trail_uid) s
    OUTER APPLY (SELECT TOP 1 a.old_value FROM #au a WHERE a.inv_mast_uid = p.inv_mast_uid AND a.location_id = p.location_id AND a.column_changed = 'inv_max'        AND a.date_created > p.entered ORDER BY a.date_created, a.audit_trail_uid) m
    OUTER APPLY (SELECT TOP 1 a.old_value FROM #au a WHERE a.inv_mast_uid = p.inv_mast_uid AND a.location_id = p.location_id AND a.column_changed = 'purchase_class' AND a.date_created > p.entered ORDER BY a.date_created, a.audit_trail_uid) k
    OUTER APPLY (SELECT TOP 1 a.date_created FROM #au a WHERE a.inv_mast_uid = p.inv_mast_uid AND a.location_id = p.location_id AND a.column_changed = 'location_id' AND a.date_created > p.entered) ad
), y AS (
    SELECT t.*,
           CASE WHEN added_after = 0 AND stockable_then = 'Y' AND max_then > 0 AND ISNULL(NULLIF(class_then, '[null]'), '') <> 'NS' THEN 1 ELSE 0 END AS stk_then,
           CASE WHEN for_order = 1 OR po_type = 'D' THEN 1 ELSE 0 END AS cust
    FROM t
), x AS (
    SELECT y.*,
           CASE WHEN y.stk_then = 0 AND y.cust = 0 AND EXISTS (
                    SELECT 1 FROM dbo.oe_line ol
                    WHERE ol.inv_mast_uid = y.inv_mast_uid AND ol.source_loc_id = y.location_id AND ol.delete_flag = 'N'
                      AND ol.date_created BETWEEN DATEADD(DAY, -@DemandDays, y.entered) AND DATEADD(DAY, @DemandDays, y.entered))
                THEN 1 ELSE 0 END AS demand
    FROM y
)
SELECT
    location_id,
    buyer,
    COUNT(DISTINCT po_no)                                                       AS pos,
    COUNT(*)                                                                    AS po_lines,
    SUM(val)                                                                    AS po_value,
    SUM(stk_now)                                                                AS stock_lines,
    SUM(CASE WHEN po_type = 'D' THEN 1 ELSE 0 END)                              AS direct_lines,
    SUM(CASE WHEN qty_received >= qty_ordered OR due < @Today THEN 1 ELSE 0 END) AS lines_judged,
    SUM(CASE WHEN qty_received >= qty_ordered AND CAST(received_date AS DATE) <= due THEN 1 ELSE 0 END) AS lines_on_time,
    SUM(stk_then)                                                               AS stk_then_lines,
    SUM(CASE WHEN stk_then = 1 THEN val ELSE 0 END)                             AS stk_then_val,
    SUM(CASE WHEN stk_then = 0 AND cust = 1 THEN 1 ELSE 0 END)                  AS ns_cust_lines,
    SUM(CASE WHEN stk_then = 0 AND cust = 1 THEN val ELSE 0 END)                AS ns_cust_val,
    SUM(CASE WHEN stk_then = 0 AND cust = 0 AND demand = 1 THEN 1 ELSE 0 END)   AS ns_demand_lines,
    SUM(CASE WHEN stk_then = 0 AND cust = 0 AND demand = 1 THEN val ELSE 0 END) AS ns_demand_val,
    SUM(CASE WHEN stk_then = 0 AND cust = 0 AND demand = 0 THEN 1 ELSE 0 END)   AS ns_shelf_lines,
    SUM(CASE WHEN stk_then = 0 AND cust = 0 AND demand = 0 THEN val ELSE 0 END) AS ns_shelf_val,
    SUM(CASE WHEN stk_then = 0 AND stk_now = 1 THEN 1 ELSE 0 END)               AS became_stk_lines,
    SUM(CASE WHEN stk_then = 0 AND stk_now = 1 THEN val ELSE 0 END)             AS became_stk_val,
    SUM(CASE WHEN stk_then = 1 AND stk_now = 0 THEN 1 ELSE 0 END)               AS dropped_stk_lines,
    SUM(CASE WHEN stk_then = 1 AND stk_now = 0 THEN val ELSE 0 END)             AS dropped_stk_val
FROM x
GROUP BY location_id, buyer;
