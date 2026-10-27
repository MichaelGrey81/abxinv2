/* ============================================
   INVENTORY VALUE HISTORY, WEEKLY  (module: inventory_history)
   Replaces the inventory_value_items_history approach in
   "Inventroy Valuation History" / "Inventroy Valuation Test". That one
   kept the last INSERT/UPDATE row per FIFO layer and ignored DELETEs, so
   layers used up before the as-of date still counted, and it rescanned the
   whole history table for every date.
   This version starts from today's open FIFO value per location (exact)
   and walks backward through weekly transaction totals. The dashboard
   rebuilds the value at the end of every week from these rows:
     value(week end) = value now - sum(net of all later weeks)
   Rows with week_start NULL and flow 'NOW' carry today's value.
   ============================================ */
SET NOCOUNT ON;
DECLARE @CompanyId    INT = 1;
DECLARE @HistoryWeeks INT = 66;   -- 52 shown, plus enough to compare the change window with the same weeks last year
DECLARE @Start DATE = DATEADD(WEEK, DATEDIFF(WEEK, 0, DATEADD(WEEK, -@HistoryWeeks, GETDATE())), 0);

SELECT
    CAST(DATEADD(WEEK, DATEDIFF(WEEK, 0, it.date_created), 0) AS DATE) AS week_start,
    it.location_id,
    CASE it.trans_type WHEN 'RECPT' THEN 'receipts' WHEN 'WO' THEN 'shipped' ELSE 'other' END AS flow,
    CAST(SUM(it.quantity * it.unit_cost_amt) AS DECIMAL(19,2)) AS value
FROM dbo.inv_tran it
WHERE it.date_created >= @Start
  AND it.location_id IN (SELECT location_id FROM dbo.location WHERE company_id = @CompanyId)
  AND it.trans_type IN ('RECPT','WO','RMA','IA','RS','TR','UNREC')
  AND it.quantity <> 0
GROUP BY DATEADD(WEEK, DATEDIFF(WEEK, 0, it.date_created), 0), it.location_id,
         CASE it.trans_type WHEN 'RECPT' THEN 'receipts' WHEN 'WO' THEN 'shipped' ELSE 'other' END

UNION ALL

SELECT NULL, fl.location_id, 'NOW', CAST(SUM(fl.fifo_layer_qty * fl.cost) AS DECIMAL(19,2))
FROM dbo.fifo_layers fl
WHERE fl.complete = 'N' AND fl.fifo_layer_qty > 0 AND fl.company_id = @CompanyId
GROUP BY fl.location_id;
