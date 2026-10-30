/* ============================================
   USAGE VS MAX BY MONTH  (module: usage_vs_max)
   Stocked item-locations at the branches (stockable, not NS, max above
   zero or min for Up To companies) whose monthly usage beat the target
   level in 2+ of the last 12 completed months. The target is the max,
   or OP + OQ for OP/OQ items, AS IT WAS at each month end (inv_loc audit
   trail: the old value of the first change after the month, otherwise
   today's value), so raising the max later doesn't hide the past.
   One row per item-location: usage and target by month (oldest first),
   today's min, max, method and cost, and the last max change in the
   window. The dashboard ranks them and suggests a new max.
   ============================================ */
SET NOCOUNT ON;
DECLARE @CompanyId  INT = 1;
DECLARE @RequireMax INT = 1;
DECLARE @To   DATE = DATEFROMPARTS(YEAR(GETDATE()), MONTH(GETDATE()), 1);   -- this month (excluded)
DECLARE @From DATE = DATEADD(MONTH, -12, @To);

DROP TABLE IF EXISTS #il, #m, #u, #au, #g;

SELECT il.inv_mast_uid, il.location_id, il.inv_min, il.inv_max, il.replenishment_method, il.purchase_class,
       il.moving_average_cost, il.qty_on_hand, il.primary_supplier_id
INTO #il
FROM dbo.inv_loc il
WHERE il.company_id = @CompanyId
  AND il.stockable = 'Y' AND ISNULL(il.delete_flag, 'N') = 'N'
  AND ISNULL(il.purchase_class, '') <> 'NS'
  AND (il.inv_max > 0 OR (@RequireMax = 0 AND il.inv_min > 0))
  AND il.location_id IN (10000,10500,11000,11500,12000,20000,21000,30000,30100,31000,31500,40000,50000,70000,71000);
CREATE CLUSTERED INDEX ix_il ON #il (inv_mast_uid, location_id);

-- the 12 completed months: 1 = oldest
SELECT demand_period_uid, beginning_date, EOMONTH(beginning_date) AS month_end, DATEDIFF(MONTH, @From, beginning_date) + 1 AS m
INTO #m
FROM dbo.demand_period
WHERE company_id = @CompanyId AND beginning_date >= @From AND beginning_date < @To;

SELECT u.inv_mast_uid, u.location_id, p.m, SUM(u.inv_period_usage) AS qty
INTO #u
FROM dbo.inv_period_usage u
JOIN #m p ON p.demand_period_uid = u.demand_period_uid
JOIN #il il ON il.inv_mast_uid = u.inv_mast_uid AND il.location_id = u.location_id
GROUP BY u.inv_mast_uid, u.location_id, p.m;

SELECT at.inv_mast_uid, TRY_CAST(at.key2_value AS DECIMAL(19,0)) AS location_id, at.column_changed, at.old_value, at.new_value,
       at.date_created, at.audit_trail_uid, at.created_by
INTO #au
FROM dbo.audit_trail at
WHERE at.table_changed = 'inv_loc'
  AND at.column_changed IN ('inv_min', 'inv_max', 'replenishment_method')
  AND at.date_created >= @From
  AND at.key2_value IN (SELECT CAST(CAST(location_id AS BIGINT) AS VARCHAR(20)) FROM dbo.location WHERE company_id = @CompanyId);
CREATE CLUSTERED INDEX ix_au ON #au (inv_mast_uid, location_id, column_changed, date_created);

-- usage and the target as of each month end
SELECT il.inv_mast_uid, il.location_id, p.m, ISNULL(u.qty, 0) AS qty,
       CASE WHEN ISNULL(md.old_value, il.replenishment_method) = 'OP/OQ'
            THEN ISNULL(TRY_CAST(mn.old_value AS DECIMAL(19,4)), il.inv_min) + ISNULL(TRY_CAST(mx.old_value AS DECIMAL(19,4)), il.inv_max)
            ELSE ISNULL(TRY_CAST(mx.old_value AS DECIMAL(19,4)), il.inv_max) END AS target
INTO #g
FROM #il il
CROSS JOIN #m p
LEFT JOIN #u u ON u.inv_mast_uid = il.inv_mast_uid AND u.location_id = il.location_id AND u.m = p.m
OUTER APPLY (SELECT TOP 1 a.old_value FROM #au a WHERE a.inv_mast_uid = il.inv_mast_uid AND a.location_id = il.location_id AND a.column_changed = 'inv_max' AND a.date_created > p.month_end ORDER BY a.date_created, a.audit_trail_uid) mx
OUTER APPLY (SELECT TOP 1 a.old_value FROM #au a WHERE a.inv_mast_uid = il.inv_mast_uid AND a.location_id = il.location_id AND a.column_changed = 'inv_min' AND a.date_created > p.month_end ORDER BY a.date_created, a.audit_trail_uid) mn
OUTER APPLY (SELECT TOP 1 a.old_value FROM #au a WHERE a.inv_mast_uid = il.inv_mast_uid AND a.location_id = il.location_id AND a.column_changed = 'replenishment_method' AND a.date_created > p.month_end ORDER BY a.date_created, a.audit_trail_uid) md;

SELECT
    g.location_id,
    im.item_id,
    im.item_desc,
    il.purchase_class,
    il.replenishment_method,
    CAST(il.inv_min AS DECIMAL(19,4))             AS inv_min,
    CAST(il.inv_max AS DECIMAL(19,4))             AS inv_max,
    CAST(il.moving_average_cost AS DECIMAL(19,4)) AS unit_cost,
    CAST(il.qty_on_hand AS DECIMAL(19,4))         AS qty_on_hand,
    s.supplier_name,
    COALESCE(NULLIF(LTRIM(RTRIM(ISNULL(sb.first_name, '') + ' ' + ISNULL(sb.last_name, ''))), ''), 'No buyer assigned') AS supplier_buyer,
    FORMAT(@From, 'yyyy-MM') AS first_month,
    CAST(SUM(CASE WHEN g.m = 1  THEN g.qty END) AS DECIMAL(19,2)) AS u01, CAST(SUM(CASE WHEN g.m = 2  THEN g.qty END) AS DECIMAL(19,2)) AS u02,
    CAST(SUM(CASE WHEN g.m = 3  THEN g.qty END) AS DECIMAL(19,2)) AS u03, CAST(SUM(CASE WHEN g.m = 4  THEN g.qty END) AS DECIMAL(19,2)) AS u04,
    CAST(SUM(CASE WHEN g.m = 5  THEN g.qty END) AS DECIMAL(19,2)) AS u05, CAST(SUM(CASE WHEN g.m = 6  THEN g.qty END) AS DECIMAL(19,2)) AS u06,
    CAST(SUM(CASE WHEN g.m = 7  THEN g.qty END) AS DECIMAL(19,2)) AS u07, CAST(SUM(CASE WHEN g.m = 8  THEN g.qty END) AS DECIMAL(19,2)) AS u08,
    CAST(SUM(CASE WHEN g.m = 9  THEN g.qty END) AS DECIMAL(19,2)) AS u09, CAST(SUM(CASE WHEN g.m = 10 THEN g.qty END) AS DECIMAL(19,2)) AS u10,
    CAST(SUM(CASE WHEN g.m = 11 THEN g.qty END) AS DECIMAL(19,2)) AS u11, CAST(SUM(CASE WHEN g.m = 12 THEN g.qty END) AS DECIMAL(19,2)) AS u12,
    CAST(MAX(CASE WHEN g.m = 1  THEN g.target END) AS DECIMAL(19,2)) AS t01, CAST(MAX(CASE WHEN g.m = 2  THEN g.target END) AS DECIMAL(19,2)) AS t02,
    CAST(MAX(CASE WHEN g.m = 3  THEN g.target END) AS DECIMAL(19,2)) AS t03, CAST(MAX(CASE WHEN g.m = 4  THEN g.target END) AS DECIMAL(19,2)) AS t04,
    CAST(MAX(CASE WHEN g.m = 5  THEN g.target END) AS DECIMAL(19,2)) AS t05, CAST(MAX(CASE WHEN g.m = 6  THEN g.target END) AS DECIMAL(19,2)) AS t06,
    CAST(MAX(CASE WHEN g.m = 7  THEN g.target END) AS DECIMAL(19,2)) AS t07, CAST(MAX(CASE WHEN g.m = 8  THEN g.target END) AS DECIMAL(19,2)) AS t08,
    CAST(MAX(CASE WHEN g.m = 9  THEN g.target END) AS DECIMAL(19,2)) AS t09, CAST(MAX(CASE WHEN g.m = 10 THEN g.target END) AS DECIMAL(19,2)) AS t10,
    CAST(MAX(CASE WHEN g.m = 11 THEN g.target END) AS DECIMAL(19,2)) AS t11, CAST(MAX(CASE WHEN g.m = 12 THEN g.target END) AS DECIMAL(19,2)) AS t12,
    SUM(CASE WHEN g.target > 0 AND g.qty > g.target THEN 1 ELSE 0 END) AS months_over,
    CAST(lc.date_created AS DATE) AS last_max_change,
    COALESCE(NULLIF(LTRIM(RTRIM(ISNULL(cc.first_name, '') + ' ' + ISNULL(cc.last_name, ''))), ''), MAX(lc.created_by)) AS last_max_by,
    TRY_CAST(MAX(lc.old_value) AS DECIMAL(19,4)) AS last_max_before,
    TRY_CAST(MAX(lc.new_value) AS DECIMAL(19,4)) AS last_max_after
FROM #g g
JOIN #il il ON il.inv_mast_uid = g.inv_mast_uid AND il.location_id = g.location_id
JOIN dbo.inv_mast im ON im.inv_mast_uid = g.inv_mast_uid
LEFT JOIN dbo.supplier s ON s.supplier_id = il.primary_supplier_id
LEFT JOIN dbo.contacts sb ON sb.id = s.buyer_id
OUTER APPLY (SELECT TOP 1 a.date_created, a.created_by, a.old_value, a.new_value FROM #au a
             WHERE a.inv_mast_uid = g.inv_mast_uid AND a.location_id = g.location_id AND a.column_changed = 'inv_max'
             ORDER BY a.date_created DESC, a.audit_trail_uid DESC) lc
LEFT JOIN dbo.users uu ON uu.id = lc.created_by
LEFT JOIN dbo.contacts cc ON cc.id = uu.contact_id
WHERE ISNULL(im.delete_flag, 'N') = 'N'
GROUP BY g.location_id, g.inv_mast_uid, im.item_id, im.item_desc, il.purchase_class, il.replenishment_method, il.inv_min, il.inv_max,
         il.moving_average_cost, il.qty_on_hand, s.supplier_name, sb.first_name, sb.last_name, lc.date_created, cc.first_name, cc.last_name
HAVING SUM(CASE WHEN g.target > 0 AND g.qty > g.target THEN 1 ELSE 0 END) >= 2;

DROP TABLE IF EXISTS #il, #m, #u, #au, #g;
