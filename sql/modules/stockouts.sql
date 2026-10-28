/* ============================================
   STOCKOUT HISTORY  (module: stockouts)
   Based on: StockoutTracker, Stockout Study
   Walks inventory transactions for stocked items at the branches over the
   last @StockoutDays. A stockout starts when on-hand drops to zero or below
   and ends at the next transaction that brings it back above zero. One row
   per item-location with event count, total days out, and whether it is
   out right now.
   ============================================ */
SET NOCOUNT ON;
DECLARE @CompanyId    INT = 1;
DECLARE @StockoutDays INT = 180;
DECLARE @RequireMax   INT = 1;     -- 1: needs max > 0 to count as stocked; 0: min > 0 is enough (Up To replenishment)
DECLARE @Start DATE = DATEADD(DAY, -@StockoutDays, CAST(GETDATE() AS DATE));

;WITH tx AS (
    SELECT
        it.inv_mast_uid,
        it.location_id,
        it.date_created,
        TRY_CAST(it.on_hand_before_trans AS DECIMAL(18,4)) + TRY_CAST(it.quantity AS DECIMAL(18,4)) AS qty_after,
        LEAD(it.date_created) OVER (PARTITION BY it.inv_mast_uid, it.location_id
                                    ORDER BY it.date_created, it.transaction_number) AS next_date,
        LEAD(TRY_CAST(it.on_hand_before_trans AS DECIMAL(18,4)) + TRY_CAST(it.quantity AS DECIMAL(18,4)))
            OVER (PARTITION BY it.inv_mast_uid, it.location_id
                  ORDER BY it.date_created, it.transaction_number) AS next_qty_after
    FROM dbo.inv_tran it
    JOIN dbo.inv_loc il ON il.inv_mast_uid = it.inv_mast_uid AND il.location_id = it.location_id
    WHERE it.date_created >= @Start
      AND it.year_for_period <> 0
      AND il.stockable = 'Y'
      AND (il.inv_max > 0 OR (@RequireMax = 0 AND il.inv_min > 0))   -- not stocked here (max 0, or no min/max for Up To companies): running out is expected
      AND il.company_id = @CompanyId
      AND ISNULL(il.purchase_class, '') <> 'NS'
      AND it.location_id IN (10000,10500,11000,11500,12000,20000,21000,30000,30100,31000,31500,40000,50000,70000,71000)
),
ev AS (
    SELECT inv_mast_uid, location_id, date_created,
           CASE WHEN next_date IS NULL THEN 1 ELSE 0 END AS ongoing,
           DATEDIFF(DAY, date_created, ISNULL(next_date, GETDATE())) AS days_out
    FROM tx
    WHERE qty_after <= 0
      AND (next_qty_after > 0 OR next_date IS NULL)
)
SELECT
    im.item_id,
    im.item_desc,
    ev.location_id,
    COUNT(*)                                     AS stockout_events,
    SUM(ev.days_out)                             AS days_out,
    CAST(MAX(ev.date_created) AS DATE)           AS last_stockout_date,
    MAX(ev.ongoing)                              AS out_now
FROM ev
JOIN dbo.inv_mast im ON im.inv_mast_uid = ev.inv_mast_uid
GROUP BY im.item_id, im.item_desc, ev.location_id;
