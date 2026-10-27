/* ============================================
   COST ON HAND BY STATUS, WEEKLY SINCE JANUARY 1  (module: status_history)
   Backfills the overview "Cost on hand over time" chart for the dates
   before the dashboard started saving daily snapshots.
   Same idea as inventory_history, but per item-location so each one can be
   classified as of each date:
     value at the start of week D = open FIFO value now
                                    - net transactions from D to today
     status as of D = days from the last invoice before D to D
                      (dead >= @DeadDays or never, slow >= @SlowDays, aging >= @AgingDays)
   Corp and consignment locations are labelled by the dashboard, as in the
   classifier. Transaction cost is the cost on the transaction, so values
   are close to, not exactly, the FIFO value on those dates.
   ============================================ */
SET NOCOUNT ON;
DECLARE @CompanyId INT = 1;
DECLARE @DeadDays  INT = 365;
DECLARE @SlowDays  INT = 180;
DECLARE @AgingDays INT = 90;
DECLARE @Today DATE = CAST(GETDATE() AS DATE);
DECLARE @From  DATE = DATEFROMPARTS(YEAR(@Today), 1, 1);

DROP TABLE IF EXISTS #d, #now, #tx, #il, #sale, #salepre, #p21, #g;

-- snapshot dates: January 1, then every 7 days
CREATE TABLE #d (snap DATE PRIMARY KEY);
DECLARE @x DATE = @From;
WHILE @x < @Today BEGIN INSERT INTO #d VALUES (@x); SET @x = DATEADD(DAY, 7, @x); END;

SELECT fl.inv_mast_uid, fl.location_id,
       SUM(fl.fifo_layer_qty) AS qty, SUM(fl.fifo_layer_qty * fl.cost) AS val
INTO #now
FROM dbo.fifo_layers fl
WHERE fl.complete = 'N' AND fl.fifo_layer_qty > 0 AND fl.company_id = @CompanyId
GROUP BY fl.inv_mast_uid, fl.location_id;

-- net movement per item-location in each 7-day bucket
SELECT it.inv_mast_uid, it.location_id,
       DATEADD(DAY, (DATEDIFF(DAY, @From, it.date_created) / 7) * 7, @From) AS snap,
       SUM(it.quantity * ISNULL(NULLIF(it.unit_size, 0), 1)) AS q,
       SUM(it.quantity * it.unit_cost_amt)                   AS v
INTO #tx
FROM dbo.inv_tran it
WHERE it.date_created >= @From
  AND it.location_id IN (SELECT location_id FROM dbo.location WHERE company_id = @CompanyId)
  AND it.trans_type IN ('RECPT','WO','RMA','IA','RS','TR','UNREC')
  AND it.quantity <> 0
GROUP BY it.inv_mast_uid, it.location_id, DATEADD(DAY, (DATEDIFF(DAY, @From, it.date_created) / 7) * 7, @From);

SELECT inv_mast_uid, location_id INTO #il FROM #now
UNION SELECT inv_mast_uid, location_id FROM #tx;

-- last invoice per item + sales location: before January 1, and the latest in each bucket after
SELECT sh.inv_mast_uid, sh.sales_location_id AS location_id, MAX(CAST(sh.invoice_date AS DATE)) AS last_sale
INTO #salepre
FROM dbo.p21_sales_history_aba_view sh
WHERE sh.invoice_date >= DATEADD(DAY, -@DeadDays, @From) AND sh.invoice_date < @From
  AND sh.company_id = @CompanyId AND ISNULL(sh.other_charge_item, 'N') <> 'Y' AND sh.qty_shipped > 0
GROUP BY sh.inv_mast_uid, sh.sales_location_id;

SELECT sh.inv_mast_uid, sh.sales_location_id AS location_id,
       DATEADD(DAY, (DATEDIFF(DAY, @From, sh.invoice_date) / 7) * 7, @From) AS snap,
       MAX(CAST(sh.invoice_date AS DATE)) AS last_sale
INTO #sale
FROM dbo.p21_sales_history_aba_view sh
WHERE sh.invoice_date >= @From
  AND sh.company_id = @CompanyId AND ISNULL(sh.other_charge_item, 'N') <> 'Y' AND sh.qty_shipped > 0
GROUP BY sh.inv_mast_uid, sh.sales_location_id, DATEADD(DAY, (DATEDIFF(DAY, @From, sh.invoice_date) / 7) * 7, @From);

-- P21's last sale date per item-location (the view can repeat an item-location)
SELECT pv.inv_mast_uid, pv.location_id, MAX(pv.last_sale_date) AS last_sale_date
INTO #p21
FROM dbo.p21_item_location_view pv
JOIN #il il ON il.inv_mast_uid = pv.inv_mast_uid AND il.location_id = pv.location_id
GROUP BY pv.inv_mast_uid, pv.location_id;

-- one row per item-location per date: value walked back from now, last sale walked forward from January 1
SELECT il.inv_mast_uid, il.location_id, d.snap,
       ISNULL(n.qty, 0) - SUM(ISNULL(t.q, 0)) OVER (PARTITION BY il.inv_mast_uid, il.location_id ORDER BY d.snap DESC ROWS UNBOUNDED PRECEDING) AS qty,
       ISNULL(n.val, 0) - SUM(ISNULL(t.v, 0)) OVER (PARTITION BY il.inv_mast_uid, il.location_id ORDER BY d.snap DESC ROWS UNBOUNDED PRECEDING) AS val,
       COALESCE(MAX(s.last_sale) OVER (PARTITION BY il.inv_mast_uid, il.location_id ORDER BY d.snap ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING),
                sp.last_sale) AS last_sale,
       CASE WHEN pv.last_sale_date > '19900101' THEN CAST(pv.last_sale_date AS DATE) END AS p21_last_sale
INTO #g
FROM #il il
CROSS JOIN #d d
LEFT JOIN #now n  ON n.inv_mast_uid = il.inv_mast_uid AND n.location_id = il.location_id
LEFT JOIN #tx t   ON t.inv_mast_uid = il.inv_mast_uid AND t.location_id = il.location_id AND t.snap = d.snap
LEFT JOIN #sale s ON s.inv_mast_uid = il.inv_mast_uid AND s.location_id = il.location_id AND s.snap = d.snap
LEFT JOIN #salepre sp ON sp.inv_mast_uid = il.inv_mast_uid AND sp.location_id = il.location_id
LEFT JOIN #p21 pv ON pv.inv_mast_uid = il.inv_mast_uid AND pv.location_id = il.location_id;

SELECT g.snap AS snapshot_date, g.location_id, x.inv_status,
       COUNT(*)                                   AS item_count,
       CAST(SUM(g.qty) AS DECIMAL(19,4)) AS qty_remaining,
       CAST(SUM(g.val) AS DECIMAL(19,2)) AS cost_on_hand
FROM #g g
-- P21's last sale date (what the classifier uses) is the latest sale ever, so when it's before the date it is the
-- last sale as of that date; invoice history only fills in dates before that last sale
CROSS APPLY (SELECT ls = CASE WHEN g.p21_last_sale < g.snap THEN g.p21_last_sale ELSE g.last_sale END) l
CROSS APPLY (SELECT dss = DATEDIFF(DAY, l.ls, g.snap)) r
CROSS APPLY (SELECT inv_status = CASE WHEN r.dss IS NULL OR r.dss >= @DeadDays THEN 'DEAD'
                                      WHEN r.dss >= @SlowDays THEN 'SLOW'
                                      WHEN r.dss >= @AgingDays THEN 'AGING'
                                      ELSE 'ACTIVE' END) x
WHERE g.val > 0.5 AND g.qty > 0
GROUP BY g.snap, g.location_id, x.inv_status
ORDER BY g.snap, g.location_id, x.inv_status;
