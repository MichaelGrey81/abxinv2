/* ============================================
   STOCKOUTS BY USAGE CLASS, BY MONTH  (module: stockout_class_monthly)
   From January of last year, for stockable items (not purchase class NS)
   at the branches, by month, branch and the item's usage class ON THE DATE
   of each event (inv_loc audit trail: the old value of the first
   purchase_class change after that date, otherwise today's value; the
   usage class is the first letter, AA..AD = A).

   Two ways to count stockouts:
     so_rule        restocked: the last transaction (any type) that left
                    on hand at <= 0 before the next one brought it back above
                    zero. A stockout only counts once it is restocked.
     still_out      stockouts not restocked yet, by the month they started;
                    still_out_max0 is how many of those had a max of 0 when
                    they ran out (not meant to be restocked).
     Including stockouts not restocked = so_rule + still_out - still_out_max0.
   Transactions: WO transactions with a quantity.
   Also, per stockout (from the transaction that took it to <= 0 until the
   next one above zero): days out, and what started it (shipment,
   adjustment, transfer/other); customer order lines entered while the item
   was out; distinct item-locations shipping / running out.
   period 'YYYY-MM' rows hold the monthly counts, 'YYYY' rows the distinct
   item-location counts for the year, 'now' rows today's on hand snapshot
   (P21 keeps no allocation history).
   ============================================ */
SET NOCOUNT ON;
DECLARE @CompanyId INT = 1;
DECLARE @Start DATE = DATEFROMPARTS(YEAR(GETDATE()) - 1, 1, 1);
DECLARE @Lead  DATE = DATEADD(MONTH, -3, @Start);    -- earlier history, so January has a starting state

DROP TABLE IF EXISTS #sb, #sau, #sam, #ssp, #sev, #sc;

SELECT it.inv_mast_uid, it.location_id, it.date_created, it.transaction_number, it.trans_type, it.quantity, il.purchase_class AS class_now,
       TRY_CAST(it.on_hand_before_trans AS DECIMAL(18,4)) AS qb,
       TRY_CAST(it.on_hand_before_trans AS DECIMAL(18,4)) + TRY_CAST(it.quantity AS DECIMAL(18,4)) AS qa
INTO #sb
FROM dbo.inv_tran it
JOIN dbo.inv_loc il ON il.inv_mast_uid = it.inv_mast_uid AND il.location_id = it.location_id
WHERE it.date_created >= @Lead
  AND it.year_for_period <> 0
  AND il.company_id = @CompanyId
  AND il.stockable = 'Y' AND ISNULL(il.purchase_class, '') <> 'NS'
  AND it.location_id IN (10000,10500,11000,11500,12000,20000,21000,30000,30100,31000,31500,40000,50000,70000,71000);
CREATE CLUSTERED INDEX ix_sb ON #sb (inv_mast_uid, location_id, date_created, transaction_number);

SELECT at.inv_mast_uid, TRY_CAST(at.key2_value AS DECIMAL(19,0)) AS location_id, at.old_value, at.date_created, at.audit_trail_uid
INTO #sau FROM dbo.audit_trail at
WHERE at.table_changed = 'inv_loc' AND at.column_changed = 'purchase_class' AND at.date_created >= @Lead;
CREATE CLUSTERED INDEX ix_sau ON #sau (inv_mast_uid, location_id, date_created);
SELECT at.inv_mast_uid, TRY_CAST(at.key2_value AS DECIMAL(19,0)) AS location_id, at.old_value, at.date_created, at.audit_trail_uid
INTO #sam FROM dbo.audit_trail at
WHERE at.table_changed = 'inv_loc' AND at.column_changed = 'inv_max' AND at.date_created >= @Lead;
CREATE CLUSTERED INDEX ix_sam ON #sam (inv_mast_uid, location_id, date_created);

-- stockouts from start to restock: the transaction that left it at <= 0 (after being above 0) to the next one above 0
;WITH x AS (
    SELECT *, LAG(qa) OVER (PARTITION BY inv_mast_uid, location_id ORDER BY date_created, transaction_number) AS prev_qa
    FROM #sb
)
SELECT x.inv_mast_uid, x.location_id, x.date_created AS out_start, x.trans_type AS start_type, e.date_created AS out_end,
       DATEDIFF(DAY, x.date_created, ISNULL(e.date_created, GETDATE())) AS days_out
INTO #ssp
FROM x
OUTER APPLY (SELECT TOP 1 b.date_created FROM #sb b WHERE b.inv_mast_uid = x.inv_mast_uid AND b.location_id = x.location_id
             AND (b.date_created > x.date_created OR (b.date_created = x.date_created AND b.transaction_number > x.transaction_number)) AND b.qa > 0
             ORDER BY b.date_created, b.transaction_number) e
WHERE x.qa <= 0 AND (x.prev_qa > 0 OR (x.prev_qa IS NULL AND x.qb > 0))
  AND (e.date_created IS NULL OR e.date_created >= @Start);
CREATE CLUSTERED INDEX ix_ssp ON #ssp (inv_mast_uid, location_id, out_start);

-- one row per counted thing, dated
SELECT CAST('wo' AS VARCHAR(8)) AS k, inv_mast_uid, location_id, date_created AS d, CAST(class_now AS VARCHAR(20)) AS class_now,
       CAST(NULL AS INT) AS days_out, CAST(0 AS INT) AS still_out, CAST(0 AS INT) AS max0, CAST(NULL AS VARCHAR(10)) AS start_type, CAST(0 AS INT) AS flag
INTO #sev FROM #sb WHERE date_created >= @Start AND trans_type = 'WO' AND quantity <> 0;

INSERT INTO #sev
SELECT 'rule', b.inv_mast_uid, b.location_id, b.date_created, b.class_now, NULL, 0, 0, NULL, 0
FROM (SELECT *, LEAD(qa) OVER (PARTITION BY inv_mast_uid, location_id ORDER BY date_created, transaction_number) AS nqa FROM #sb) b
WHERE b.date_created >= @Start AND b.qa <= 0 AND b.nqa > 0;

INSERT INTO #sev
SELECT 'spell', s.inv_mast_uid, s.location_id, CASE WHEN s.out_start < @Start THEN @Start ELSE s.out_start END, il.purchase_class,
       s.days_out, CASE WHEN s.out_end IS NULL THEN 1 ELSE 0 END,
       CASE WHEN ISNULL(TRY_CAST(m.old_value AS DECIMAL(19,4)), il.inv_max) <= 0 THEN 1 ELSE 0 END, s.start_type, 0
FROM #ssp s
JOIN dbo.inv_loc il ON il.inv_mast_uid = s.inv_mast_uid AND il.location_id = s.location_id
OUTER APPLY (SELECT TOP 1 a.old_value FROM #sam a WHERE a.inv_mast_uid = s.inv_mast_uid AND a.location_id = s.location_id AND a.date_created > s.out_start ORDER BY a.date_created, a.audit_trail_uid) m;

-- customer order lines (as fill_rate.sql counts them) and whether the item was out when the line was entered
INSERT INTO #sev
SELECT 'line', ol.inv_mast_uid, ol.source_loc_id, ol.date_created, il.purchase_class, NULL, 0, 0, NULL,
       CASE WHEN EXISTS (SELECT 1 FROM #ssp s WHERE s.inv_mast_uid = ol.inv_mast_uid AND s.location_id = ol.source_loc_id
                         AND s.out_start <= ol.date_created AND (s.out_end IS NULL OR s.out_end > ol.date_created)) THEN 1 ELSE 0 END
FROM dbo.oe_line ol
JOIN dbo.oe_hdr oh ON oh.order_no = ol.order_no
JOIN dbo.inv_loc il ON il.inv_mast_uid = ol.inv_mast_uid AND il.location_id = ol.source_loc_id
WHERE ol.date_created >= @Start
  AND oh.company_id = @CompanyId
  AND ISNULL(oh.delete_flag, 'N') = 'N' AND ISNULL(ol.delete_flag, 'N') = 'N'
  AND ISNULL(oh.projected_order, 'N') = 'N' AND ISNULL(oh.rma_flag, 'N') = 'N'
  AND ISNULL(ol.disposition, '') NOT IN ('D', 'S') AND ol.qty_ordered > 0
  AND il.stockable = 'Y' AND ISNULL(il.purchase_class, '') <> 'NS'
  AND ol.source_loc_id IN (10000,10500,11000,11500,12000,20000,21000,30000,30100,31000,31500,40000,50000,70000,71000);

SELECT e.*, FORMAT(e.d, 'yyyy-MM') AS mon,
       CASE WHEN cl.cls LIKE '[A-E]' OR cl.cls LIKE '[A-E][A-E]' OR cl.cls LIKE '[A-E][0-9]%' THEN LEFT(cl.cls, 1)
            WHEN cl.cls = 'XX'           THEN 'XX'
            WHEN cl.cls LIKE 'N[0-9]%'   THEN 'N##'
            WHEN cl.cls LIKE 'S[0-9]%'   THEN 'S###'
            WHEN ISNULL(cl.cls, '') = '' THEN '(blank)'
            ELSE 'Other' END AS usage_class
INTO #sc
FROM #sev e
OUTER APPLY (SELECT TOP 1 a.old_value FROM #sau a WHERE a.inv_mast_uid = e.inv_mast_uid AND a.location_id = e.location_id AND a.date_created > e.d ORDER BY a.date_created, a.audit_trail_uid) k
CROSS APPLY (SELECT ISNULL(k.old_value, e.class_now) AS cls) cl;

SELECT mon AS period, location_id, usage_class,
    SUM(CASE WHEN k = 'wo' THEN 1 ELSE 0 END)                                           AS wo_tx,
    SUM(CASE WHEN k = 'rule' THEN 1 ELSE 0 END)                                         AS so_rule,
    SUM(CASE WHEN k = 'spell' THEN still_out ELSE 0 END)                                AS still_out,
    SUM(CASE WHEN k = 'spell' AND still_out = 1 THEN max0 ELSE 0 END)                   AS still_out_max0,
    SUM(CASE WHEN k = 'spell' THEN 1 ELSE 0 END)                                        AS outs,
    SUM(CASE WHEN k = 'spell' THEN days_out ELSE 0 END)                                 AS days_out,
    SUM(CASE WHEN k = 'spell' AND still_out = 0 THEN 1 ELSE 0 END)                      AS outs_restocked,
    SUM(CASE WHEN k = 'spell' AND still_out = 0 THEN days_out ELSE 0 END)               AS days_out_restocked,
    SUM(CASE WHEN k = 'spell' AND start_type = 'IA' THEN 1 ELSE 0 END)                  AS started_by_adjustment,
    SUM(CASE WHEN k = 'spell' AND start_type NOT IN ('WO', 'IA') THEN 1 ELSE 0 END)     AS started_by_transfer_other,
    SUM(CASE WHEN k = 'line' THEN 1 ELSE 0 END)                                         AS order_lines,
    SUM(CASE WHEN k = 'line' THEN flag ELSE 0 END)                                      AS lines_while_out,
    COUNT(DISTINCT CASE WHEN k = 'wo' THEN inv_mast_uid END)                            AS items_shipping,
    COUNT(DISTINCT CASE WHEN k = 'spell' THEN inv_mast_uid END)                         AS items_out,
    CAST(NULL AS INT) AS snap_items, CAST(NULL AS INT) AS snap_zero, CAST(NULL AS INT) AS snap_allocated
FROM #sc GROUP BY mon, location_id, usage_class
UNION ALL
-- distinct item-locations for the whole year (an item can't be added up across months)
SELECT LEFT(mon, 4), location_id, usage_class, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    COUNT(DISTINCT CASE WHEN k = 'wo' THEN inv_mast_uid END),
    COUNT(DISTINCT CASE WHEN k = 'spell' THEN inv_mast_uid END), NULL, NULL, NULL
FROM #sc GROUP BY LEFT(mon, 4), location_id, usage_class
UNION ALL
-- today: stocked item-locations at zero, and those with stock on hand that is all allocated
SELECT 'now', il.location_id,
    CASE WHEN il.purchase_class LIKE '[A-E]' OR il.purchase_class LIKE '[A-E][A-E]' OR il.purchase_class LIKE '[A-E][0-9]%' THEN LEFT(il.purchase_class, 1)
         WHEN il.purchase_class = 'XX' THEN 'XX' WHEN il.purchase_class LIKE 'N[0-9]%' THEN 'N##' WHEN il.purchase_class LIKE 'S[0-9]%' THEN 'S###'
         WHEN ISNULL(il.purchase_class, '') = '' THEN '(blank)' ELSE 'Other' END,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    COUNT(*),
    SUM(CASE WHEN il.qty_on_hand <= 0 THEN 1 ELSE 0 END),
    SUM(CASE WHEN il.qty_on_hand > 0 AND il.qty_on_hand - ISNULL(il.qty_allocated, 0) <= 0 THEN 1 ELSE 0 END)
FROM dbo.inv_loc il
WHERE il.company_id = @CompanyId
  AND il.stockable = 'Y' AND ISNULL(il.purchase_class, '') <> 'NS' AND il.inv_max > 0
  AND il.location_id IN (10000,10500,11000,11500,12000,20000,21000,30000,30100,31000,31500,40000,50000,70000,71000)
GROUP BY il.location_id,
    CASE WHEN il.purchase_class LIKE '[A-E]' OR il.purchase_class LIKE '[A-E][A-E]' OR il.purchase_class LIKE '[A-E][0-9]%' THEN LEFT(il.purchase_class, 1)
         WHEN il.purchase_class = 'XX' THEN 'XX' WHEN il.purchase_class LIKE 'N[0-9]%' THEN 'N##' WHEN il.purchase_class LIKE 'S[0-9]%' THEN 'S###'
         WHEN ISNULL(il.purchase_class, '') = '' THEN '(blank)' ELSE 'Other' END;

DROP TABLE IF EXISTS #sb, #sau, #sam, #ssp, #sev, #sc;
