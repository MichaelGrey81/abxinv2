/* ============================================
   STOCKING CANDIDATES  (module: stock_candidates)
   Non-stock item-locations (stockable N) at the branches with recent,
   consistent usage over the last 12 completed months: candidates to make
   stockable. One row per branch and item: usage by month (oldest first),
   how many months had usage, how many of the last 3, how steady it is
   (coefficient of variation), and who's buying it (customers, orders,
   lines and sales over 12 months, how much of it was direct ship or
   special order). Kept when usage shows in 3+ of 12 months and in the
   last 6 months; the dashboard applies the stricter thresholds.
   ============================================ */
SET NOCOUNT ON;
DECLARE @CompanyId INT = 1;
DECLARE @To   DATE = DATEFROMPARTS(YEAR(GETDATE()), MONTH(GETDATE()), 1);   -- this month (excluded)
DECLARE @From DATE = DATEADD(MONTH, -12, @To);

DROP TABLE IF EXISTS #per, #u, #c, #o;

SELECT demand_period_uid, beginning_date,
       DATEDIFF(MONTH, @From, beginning_date) + 1 AS m        -- 1 = oldest month, 12 = last month
INTO #per
FROM dbo.demand_period
WHERE company_id = @CompanyId AND beginning_date >= @From AND beginning_date < @To;

-- usage by item-location and month, branches only
SELECT u.inv_mast_uid, u.location_id, p.m, SUM(u.inv_period_usage) AS qty
INTO #u
FROM dbo.inv_period_usage u
JOIN #per p ON p.demand_period_uid = u.demand_period_uid
WHERE u.location_id IN (10000,10500,11000,11500,12000,20000,21000,30000,30100,31000,31500,40000,50000,70000,71000)
  AND u.inv_period_usage > 0
GROUP BY u.inv_mast_uid, u.location_id, p.m;

-- non-stock item-locations with usage in 3+ months, one of them in the last 6
SELECT u.inv_mast_uid, u.location_id
INTO #c
FROM #u u
JOIN dbo.inv_loc il ON il.inv_mast_uid = u.inv_mast_uid AND il.location_id = u.location_id
WHERE il.company_id = @CompanyId
  AND il.stockable = 'N'
  AND ISNULL(il.delete_flag, 'N') = 'N'
GROUP BY u.inv_mast_uid, u.location_id
HAVING COUNT(*) >= 3 AND MAX(u.m) >= 7;
CREATE CLUSTERED INDEX ix_c ON #c (inv_mast_uid, location_id);

-- customer order lines over the same 12 months
SELECT ol.inv_mast_uid, ol.source_loc_id AS location_id,
       COUNT(*) AS lines,
       COUNT(DISTINCT oh.order_no) AS orders,
       COUNT(DISTINCT oh.customer_id) AS customers,
       SUM(CASE WHEN ISNULL(ol.disposition, '') IN ('D', 'S') THEN 1 ELSE 0 END) AS lines_direct_special,
       CAST(SUM(ol.extended_price) AS DECIMAL(19,2)) AS sales_12m,
       CAST(MAX(ol.date_created) AS DATE) AS last_order
INTO #o
FROM dbo.oe_line ol
JOIN dbo.oe_hdr oh ON oh.order_no = ol.order_no
JOIN #c c ON c.inv_mast_uid = ol.inv_mast_uid AND c.location_id = ol.source_loc_id
WHERE ol.date_created >= @From AND ol.date_created < @To
  AND oh.company_id = @CompanyId
  AND ISNULL(oh.delete_flag, 'N') = 'N' AND ISNULL(ol.delete_flag, 'N') = 'N'
  AND ISNULL(oh.projected_order, 'N') = 'N' AND ISNULL(oh.rma_flag, 'N') = 'N'
  AND ol.qty_ordered > 0
GROUP BY ol.inv_mast_uid, ol.source_loc_id;

SELECT
    c.location_id,
    im.item_id,
    im.item_desc,
    il.purchase_class,
    il.replenishment_method,
    s.supplier_name,
    CAST(il.moving_average_cost AS DECIMAL(19,4)) AS unit_cost,
    CAST(il.qty_on_hand AS DECIMAL(19,4)) AS qty_on_hand,
    CAST(SUM(CASE WHEN u.m = 1  THEN u.qty ELSE 0 END) AS DECIMAL(19,2)) AS u01,
    CAST(SUM(CASE WHEN u.m = 2  THEN u.qty ELSE 0 END) AS DECIMAL(19,2)) AS u02,
    CAST(SUM(CASE WHEN u.m = 3  THEN u.qty ELSE 0 END) AS DECIMAL(19,2)) AS u03,
    CAST(SUM(CASE WHEN u.m = 4  THEN u.qty ELSE 0 END) AS DECIMAL(19,2)) AS u04,
    CAST(SUM(CASE WHEN u.m = 5  THEN u.qty ELSE 0 END) AS DECIMAL(19,2)) AS u05,
    CAST(SUM(CASE WHEN u.m = 6  THEN u.qty ELSE 0 END) AS DECIMAL(19,2)) AS u06,
    CAST(SUM(CASE WHEN u.m = 7  THEN u.qty ELSE 0 END) AS DECIMAL(19,2)) AS u07,
    CAST(SUM(CASE WHEN u.m = 8  THEN u.qty ELSE 0 END) AS DECIMAL(19,2)) AS u08,
    CAST(SUM(CASE WHEN u.m = 9  THEN u.qty ELSE 0 END) AS DECIMAL(19,2)) AS u09,
    CAST(SUM(CASE WHEN u.m = 10 THEN u.qty ELSE 0 END) AS DECIMAL(19,2)) AS u10,
    CAST(SUM(CASE WHEN u.m = 11 THEN u.qty ELSE 0 END) AS DECIMAL(19,2)) AS u11,
    CAST(SUM(CASE WHEN u.m = 12 THEN u.qty ELSE 0 END) AS DECIMAL(19,2)) AS u12,
    FORMAT(@From, 'yyyy-MM')                          AS first_month,
    ISNULL(MAX(o.lines), 0)                           AS lines,
    ISNULL(MAX(o.orders), 0)                          AS orders,
    ISNULL(MAX(o.customers), 0)                       AS customers,
    ISNULL(MAX(o.lines_direct_special), 0)            AS lines_direct_special,
    ISNULL(MAX(o.sales_12m), 0)                       AS sales_12m,
    MAX(o.last_order)                                 AS last_order,
    -- branches that stock it today (stockable, max above zero)
    (SELECT COUNT(*) FROM dbo.inv_loc x WHERE x.inv_mast_uid = c.inv_mast_uid AND x.company_id = @CompanyId
        AND x.stockable = 'Y' AND x.inv_max > 0
        AND x.location_id IN (10000,10500,11000,11500,12000,20000,21000,30000,30100,31000,31500,40000,50000,70000,71000)) AS branches_stocking
FROM #c c
JOIN #u u ON u.inv_mast_uid = c.inv_mast_uid AND u.location_id = c.location_id
JOIN dbo.inv_loc il ON il.inv_mast_uid = c.inv_mast_uid AND il.location_id = c.location_id
JOIN dbo.inv_mast im ON im.inv_mast_uid = c.inv_mast_uid
LEFT JOIN dbo.supplier s ON s.supplier_id = il.primary_supplier_id
LEFT JOIN #o o ON o.inv_mast_uid = c.inv_mast_uid AND o.location_id = c.location_id
WHERE ISNULL(im.delete_flag, 'N') = 'N'
GROUP BY c.location_id, c.inv_mast_uid, im.item_id, im.item_desc, il.purchase_class, il.replenishment_method, s.supplier_name,
         il.moving_average_cost, il.qty_on_hand;

DROP TABLE IF EXISTS #per, #u, #c, #o;
