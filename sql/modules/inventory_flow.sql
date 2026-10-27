/* ============================================
   WHAT MOVED INVENTORY VALUE  (module: inventory_flow)
   One row per item-location with the value and quantity that flowed in
   and out over the last @ChangeDays ("cur") and the @ChangeDays before
   that ("prev"), from inventory transactions (inv_tran, quantity x
   unit_cost_amt, signed). FIFO value only changes through these
   transactions, so cur_net is how much each item-location added to or
   removed from inventory value in the window.
     RECPT = PO receipts            WO  = shipped to customers
     RMA   = customer returns       IA  = inventory adjustments
     RS    = returned to supplier   TR  = transfers (net of in and out)
   ============================================ */
SET NOCOUNT ON;
DECLARE @CompanyId  INT = 1;
DECLARE @ChangeDays INT = 61;
DECLARE @Now  DATETIME = CAST(CAST(GETDATE() AS DATE) AS DATETIME);   -- windows start at midnight
DECLARE @Cur  DATETIME = DATEADD(DAY, -@ChangeDays, @Now);
DECLARE @Prev DATETIME = DATEADD(DAY, -2 * @ChangeDays, @Now);

;WITH t AS (
    SELECT it.inv_mast_uid, it.location_id, it.trans_type,
           CASE WHEN it.date_created >= @Cur THEN 1 ELSE 0 END AS is_cur,
           CAST(it.quantity AS DECIMAL(19,4))                   AS qty,
           CAST(it.quantity * it.unit_cost_amt AS DECIMAL(19,4)) AS val
    FROM dbo.inv_tran it
    WHERE it.date_created >= @Prev
      AND it.location_id IN (SELECT location_id FROM dbo.location WHERE company_id = @CompanyId)
      AND it.trans_type IN ('RECPT','WO','RMA','IA','RS','TR','UNREC')
      AND it.quantity <> 0
)
SELECT
    im.item_id,
    t.location_id,
    CAST(SUM(CASE WHEN is_cur = 1 AND trans_type = 'RECPT' THEN val ELSE 0 END) AS DECIMAL(19,2)) AS cur_receipts,
    CAST(SUM(CASE WHEN is_cur = 1 AND trans_type = 'RECPT' THEN qty ELSE 0 END) AS DECIMAL(19,4)) AS cur_receipts_qty,
    CAST(SUM(CASE WHEN is_cur = 1 AND trans_type = 'WO'    THEN val ELSE 0 END) AS DECIMAL(19,2)) AS cur_shipped,
    CAST(SUM(CASE WHEN is_cur = 1 AND trans_type = 'WO'    THEN qty ELSE 0 END) AS DECIMAL(19,4)) AS cur_shipped_qty,
    CAST(SUM(CASE WHEN is_cur = 1 AND trans_type = 'RMA'   THEN val ELSE 0 END) AS DECIMAL(19,2)) AS cur_returns_in,
    CAST(SUM(CASE WHEN is_cur = 1 AND trans_type = 'IA'    THEN val ELSE 0 END) AS DECIMAL(19,2)) AS cur_adjust,
    CAST(SUM(CASE WHEN is_cur = 1 AND trans_type IN ('RS','UNREC') THEN val ELSE 0 END) AS DECIMAL(19,2)) AS cur_to_supplier,
    CAST(SUM(CASE WHEN is_cur = 1 AND trans_type = 'TR'    THEN val ELSE 0 END) AS DECIMAL(19,2)) AS cur_transfer,
    CAST(SUM(CASE WHEN is_cur = 1 THEN val ELSE 0 END) AS DECIMAL(19,2))                          AS cur_net,
    CAST(SUM(CASE WHEN is_cur = 0 AND trans_type = 'RECPT' THEN val ELSE 0 END) AS DECIMAL(19,2)) AS prev_receipts,
    CAST(SUM(CASE WHEN is_cur = 0 AND trans_type = 'WO'    THEN val ELSE 0 END) AS DECIMAL(19,2)) AS prev_shipped,
    CAST(SUM(CASE WHEN is_cur = 0 THEN val ELSE 0 END) AS DECIMAL(19,2))                          AS prev_net
FROM t
JOIN dbo.inv_mast im ON im.inv_mast_uid = t.inv_mast_uid
GROUP BY im.item_id, t.location_id
HAVING SUM(ABS(val)) > 0;
