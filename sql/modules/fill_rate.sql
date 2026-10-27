/* ============================================
   CUSTOMER FILL RATE  (module: fill_rate)
   Did customer order lines for stocked items ship complete from stock?
   A line counts as FILLED when its full quantity shipped (pick ticket ship
   quantity) within @FillWindowDays business days of the line being entered.
   Also reported: lines that shipped complete on their first shipment, however
   long that took (separates timing from real shortages).
   P21 keeps no history of what was allocated at order entry
   (oe_line.original_qty_allocated is empty here), and the order date is
   reset when an order is released, so the line's own entry date
   (oe_line.date_created) and pick ticket dates are used instead.

   Counted: stocked item-locations (stockable = Y, max > 0, or min > 0 for
   Up To companies, not purchase class NS) at the line's source location.
   Left out: direct ship (D) and special order (S) lines, quotes, RMAs,
   deleted lines, and lines the customer asked for later than the window
   (required_date). Lines entered in the last @FillWindowDays days are not
   judged yet. Lines fully canceled with nothing shipped are counted
   separately and left out of the rates.

   One row per item-location.
   ============================================ */
SET NOCOUNT ON;
DECLARE @CompanyId      INT = 1;
DECLARE @RequireMax     INT = 1;
DECLARE @FillDays       INT = 178;  -- with the 2-day window this covers the same 180 days as the stockout analysis
DECLARE @FillWindowDays INT = 2;    -- filled = shipped complete within this many business days of entry
DECLARE @End   DATETIME = DATEADD(DAY, -@FillWindowDays, CAST(GETDATE() AS DATE));
DECLARE @Start DATETIME = DATEADD(DAY, -@FillDays, @End);

-- business-day deadline for each entry date: the end of the Nth weekday after it (Mon-Fri; holidays are not excluded)
DROP TABLE IF EXISTS #bd;
;WITH n AS (SELECT TOP (DATEDIFF(DAY, @Start, @End) + 30) ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) - 1 AS i FROM sys.all_objects),
      d AS (SELECT CAST(DATEADD(DAY, i, DATEADD(DAY, -1, @Start)) AS DATE) AS d FROM n),
      w AS (SELECT d, CASE WHEN (DATEPART(WEEKDAY, d) + @@DATEFIRST - 2) % 7 < 5 THEN 1 ELSE 0 END AS wk FROM d)
SELECT a.d, (SELECT MIN(b.d) FROM w b WHERE b.d > a.d AND (SELECT SUM(c.wk) FROM w c WHERE c.d > a.d AND c.d <= b.d) >= @FillWindowDays) AS deadline
INTO #bd FROM w a;

DROP TABLE IF EXISTS #fl, #fs, #fx;

SELECT ol.order_no, ol.line_no, ol.inv_mast_uid, ol.source_loc_id AS location_id, ol.date_created AS entered,
       DATEADD(DAY, DATEDIFF(DAY, CAST(ol.date_created AS DATE), bd.deadline), ol.date_created) AS deadline, oh.customer_id,
       CAST(ol.qty_ordered AS DECIMAL(19,4))                    AS qty,
       CAST(ISNULL(ol.qty_canceled, 0) AS DECIMAL(19,4))        AS qty_canceled,
       CAST(CASE WHEN ol.qty_ordered > 0 THEN ol.extended_price / ol.qty_ordered ELSE 0 END AS DECIMAL(19,4)) AS price,
       ISNULL(ol.complete, 'N')                                 AS complete,
       ISNULL(ol.disposition, '')                               AS disposition
INTO #fl
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
CREATE CLUSTERED INDEX ix_fl ON #fl (order_no, line_no);

-- every shipment against those lines (pick tickets are reprinted with zero shipped; those are skipped)
SELECT pt.order_no, pd.oe_line_no AS line_no, COALESCE(pt.ship_date, pt.date_created) AS shipped, CAST(pd.ship_quantity AS DECIMAL(19,4)) AS q
INTO #fs
FROM dbo.oe_pick_ticket pt
JOIN dbo.oe_pick_ticket_detail pd ON pd.pick_ticket_no = pt.pick_ticket_no
WHERE pd.ship_quantity > 0
  AND ISNULL(pt.delete_flag, 'N') = 'N'
  AND pt.order_no IN (SELECT DISTINCT order_no FROM #fl);
CREATE CLUSTERED INDEX ix_fs ON #fs (order_no, line_no, shipped);

-- per line: shipped inside the window, shipped in total, and the date it was complete
SELECT l.*,
       ISNULL(w.q, 0) AS q_window,
       ISNULL(t.q, 0) AS q_total,
       c.complete_dt,
       ISNULL(f1.q, 0) AS q_first,
       CASE WHEN ISNULL(w.q, 0) >= l.qty - 0.0001                                   THEN 'filled'
            WHEN ISNULL(t.q, 0) = 0 AND l.qty_canceled >= l.qty - 0.0001            THEN 'canceled'
            WHEN ISNULL(w.q, 0) > 0                                                 THEN 'partial'
            WHEN c.complete_dt IS NOT NULL                                          THEN 'late'
            ELSE 'open' END AS status
INTO #fx
FROM #fl l
OUTER APPLY (SELECT SUM(s.q) q FROM #fs s WHERE s.order_no = l.order_no AND s.line_no = l.line_no AND s.shipped < l.deadline) w
OUTER APPLY (SELECT SUM(s.q) q FROM #fs s WHERE s.order_no = l.order_no AND s.line_no = l.line_no) t
OUTER APPLY (SELECT MIN(CAST(s.shipped AS DATE)) d FROM #fs s WHERE s.order_no = l.order_no AND s.line_no = l.line_no) f0
OUTER APPLY (SELECT SUM(s.q) q FROM #fs s WHERE s.order_no = l.order_no AND s.line_no = l.line_no AND CAST(s.shipped AS DATE) = f0.d) f1
OUTER APPLY (SELECT TOP 1 x.shipped AS complete_dt
             FROM (SELECT s.shipped, SUM(s.q) OVER (ORDER BY s.shipped ROWS UNBOUNDED PRECEDING) AS cum
                   FROM #fs s WHERE s.order_no = l.order_no AND s.line_no = l.line_no) x
             WHERE x.cum >= l.qty - 0.0001 ORDER BY x.shipped) c;

SELECT
    im.item_id,
    im.item_desc,
    x.location_id,
    COUNT(*)                                                                   AS lines,
    SUM(CASE WHEN x.status = 'filled'   THEN 1 ELSE 0 END)                     AS lines_filled,
    SUM(CASE WHEN x.status = 'partial'  THEN 1 ELSE 0 END)                     AS lines_partial,
    SUM(CASE WHEN x.status = 'late'     THEN 1 ELSE 0 END)                     AS lines_late,
    SUM(CASE WHEN x.status = 'open'     THEN 1 ELSE 0 END)                     AS lines_open,
    SUM(CASE WHEN x.status = 'canceled' THEN 1 ELSE 0 END)                     AS lines_canceled,
    SUM(CASE WHEN x.status <> 'canceled' AND x.q_first >= x.qty - 0.0001 THEN 1 ELSE 0 END) AS lines_first_ship_full,
    COUNT(DISTINCT CASE WHEN x.status <> 'canceled' THEN x.order_no END)       AS orders,
    COUNT(DISTINCT CASE WHEN x.status <> 'canceled' THEN x.customer_id END)    AS customers,
    COUNT(DISTINCT CASE WHEN x.status IN ('partial', 'late', 'open') THEN x.customer_id END) AS customers_shorted,
    CAST(SUM(CASE WHEN x.status <> 'canceled' THEN x.qty ELSE 0 END) AS DECIMAL(19,4))                                   AS qty_ordered,
    CAST(SUM(CASE WHEN x.status <> 'canceled' THEN CASE WHEN x.q_window > x.qty THEN x.qty ELSE x.q_window END ELSE 0 END) AS DECIMAL(19,4)) AS qty_filled,
    CAST(SUM(CASE WHEN x.status <> 'canceled' THEN x.qty * x.price ELSE 0 END) AS DECIMAL(19,2))                        AS value_ordered,
    CAST(SUM(CASE WHEN x.status <> 'canceled' THEN CASE WHEN x.q_window > x.qty THEN x.qty ELSE x.q_window END * x.price ELSE 0 END) AS DECIMAL(19,2)) AS value_filled,
    CAST(AVG(CASE WHEN x.status IN ('partial', 'late') AND x.complete_dt IS NOT NULL
                  THEN DATEDIFF(HOUR, x.entered, x.complete_dt) / 24.0 END) AS DECIMAL(9,1))                            AS avg_days_to_complete_missed,
    CAST(MAX(CASE WHEN x.status IN ('partial', 'late', 'open') THEN x.entered END) AS DATE)                              AS last_miss
FROM #fx x
JOIN dbo.inv_mast im ON im.inv_mast_uid = x.inv_mast_uid
GROUP BY im.item_id, im.item_desc, x.location_id;
