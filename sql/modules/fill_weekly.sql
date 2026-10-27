/* ============================================
   CUSTOMER FILL RATE BY WEEK  (module: fill_weekly)
   Same rules as fill_rate (stocked items, shipped complete within
   @FillWindowDays days of the line being entered), totaled by the week the
   line was entered (weeks start Monday) and location, for the trend chart.
   ============================================ */
SET NOCOUNT ON;
DECLARE @CompanyId      INT = 1;
DECLARE @RequireMax     INT = 1;
DECLARE @FillDays       INT = 182;  -- 26 weeks of trend
DECLARE @FillWindowDays INT = 2;
DECLARE @End   DATETIME = DATEADD(DAY, -@FillWindowDays, CAST(GETDATE() AS DATE));
DECLARE @Start DATETIME = DATEADD(DAY, -@FillDays, @End);

-- business-day deadline for each entry date: the end of the Nth weekday after it (Mon-Fri; holidays are not excluded)
DROP TABLE IF EXISTS #bd;
;WITH n AS (SELECT TOP (DATEDIFF(DAY, @Start, @End) + 30) ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) - 1 AS i FROM sys.all_objects),
      d AS (SELECT CAST(DATEADD(DAY, i, DATEADD(DAY, -1, @Start)) AS DATE) AS d FROM n),
      w AS (SELECT d, CASE WHEN (DATEPART(WEEKDAY, d) + @@DATEFIRST - 2) % 7 < 5 THEN 1 ELSE 0 END AS wk FROM d)
SELECT a.d, (SELECT MIN(b.d) FROM w b WHERE b.d > a.d AND (SELECT SUM(c.wk) FROM w c WHERE c.d > a.d AND c.d <= b.d) >= @FillWindowDays) AS deadline
INTO #bd FROM w a;

DROP TABLE IF EXISTS #wl, #ws;

SELECT ol.order_no, ol.line_no, ol.source_loc_id AS location_id, ol.date_created AS entered,
       DATEADD(DAY, DATEDIFF(DAY, CAST(ol.date_created AS DATE), bd.deadline), ol.date_created) AS deadline,
       CAST(ol.qty_ordered AS DECIMAL(19,4)) AS qty, CAST(ISNULL(ol.qty_canceled, 0) AS DECIMAL(19,4)) AS qty_canceled,
       CAST(CASE WHEN ol.qty_ordered > 0 THEN ol.extended_price / ol.qty_ordered ELSE 0 END AS DECIMAL(19,4)) AS price
INTO #wl
FROM dbo.oe_line ol
JOIN dbo.oe_hdr  oh ON oh.order_no = ol.order_no
JOIN dbo.inv_loc il ON il.inv_mast_uid = ol.inv_mast_uid AND il.location_id = ol.source_loc_id
JOIN #bd bd ON bd.d = CAST(ol.date_created AS DATE)
WHERE oh.company_id = @CompanyId
  AND il.company_id = @CompanyId
  AND ol.date_created >= @Start AND ol.date_created < @End
  AND ISNULL(oh.delete_flag, 'N') = 'N' AND ISNULL(ol.delete_flag, 'N') = 'N'
  AND ISNULL(oh.projected_order, 'N') = 'N' AND ISNULL(oh.rma_flag, 'N') = 'N'
  AND ISNULL(ol.disposition, '') NOT IN ('D', 'S')
  AND ol.qty_ordered > 0
  AND (ol.required_date IS NULL OR CAST(ol.required_date AS DATE) <= bd.deadline)   -- customer asked for it later than the window: can't be judged
  AND bd.deadline < CAST(GETDATE() AS DATE)                                          -- window still open: not judged yet
  AND il.stockable = 'Y'
  AND (il.inv_max > 0 OR (@RequireMax = 0 AND il.inv_min > 0))
  AND ISNULL(il.purchase_class, '') <> 'NS';
CREATE CLUSTERED INDEX ix_wl ON #wl (order_no, line_no);

SELECT pt.order_no, pd.oe_line_no AS line_no, COALESCE(pt.ship_date, pt.date_created) AS shipped, CAST(pd.ship_quantity AS DECIMAL(19,4)) AS q
INTO #ws
FROM dbo.oe_pick_ticket pt
JOIN dbo.oe_pick_ticket_detail pd ON pd.pick_ticket_no = pt.pick_ticket_no
WHERE pd.ship_quantity > 0
  AND ISNULL(pt.delete_flag, 'N') = 'N'
  AND pt.order_no IN (SELECT DISTINCT order_no FROM #wl);
CREATE CLUSTERED INDEX ix_ws ON #ws (order_no, line_no, shipped);

SELECT
    CAST(DATEADD(DAY, -((DATEPART(WEEKDAY, x.entered) + @@DATEFIRST - 2) % 7), CAST(x.entered AS DATE)) AS DATE) AS week,
    x.location_id,
    COUNT(*)                                                                      AS lines,
    SUM(CASE WHEN x.qw >= x.qty - 0.0001 THEN 1 ELSE 0 END)                       AS lines_filled,
    CAST(SUM(x.qty * x.price) AS DECIMAL(19,2))                                   AS value_ordered,
    CAST(SUM(CASE WHEN x.qw > x.qty THEN x.qty ELSE x.qw END * x.price) AS DECIMAL(19,2)) AS value_filled
FROM (
    SELECT l.*, ISNULL(w.q, 0) AS qw, ISNULL(t.q, 0) AS qt
    FROM #wl l
    OUTER APPLY (SELECT SUM(s.q) q FROM #ws s WHERE s.order_no = l.order_no AND s.line_no = l.line_no AND s.shipped < l.deadline) w
    OUTER APPLY (SELECT SUM(s.q) q FROM #ws s WHERE s.order_no = l.order_no AND s.line_no = l.line_no) t
) x
WHERE NOT (x.qt = 0 AND x.qty_canceled >= x.qty - 0.0001)   -- fully canceled, nothing shipped: left out, as in fill_rate
GROUP BY CAST(DATEADD(DAY, -((DATEPART(WEEKDAY, x.entered) + @@DATEFIRST - 2) % 7), CAST(x.entered AS DATE)) AS DATE), x.location_id;
