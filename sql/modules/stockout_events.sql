/* ============================================
   STOCKOUT ROOT-CAUSE DETAIL  (module: stockout_events)
   Based on: StockoutTracker, Stockout Study, Critical Item Not on PO
   One row per stockout event at a branch over the last @StockoutDays.
   Only stockable items with a max above zero count: items flagged
   non-stockable or with max 0 are expected to run out and are left out.
   A stockout starts when on hand drops to zero or below and ends at the
   next transaction that brings it back above zero. For each event:
     - the PO that was already open when it ran out (if any), its due date
       and when it was received, to tell "supplier late" from "ordered late"
     - the first PO created after it ran out, to measure reaction time
     - the min, max, method, safety stock and average monthly usage now
   The dashboard turns these into a root cause, lost sales and repeat
   offenders.
   ============================================ */
SET NOCOUNT ON;
DECLARE @CompanyId    INT = 1;
DECLARE @StockoutDays INT = 180;
DECLARE @RequireMax   INT = 1;     -- 1: needs max > 0 to count as stocked; 0: min > 0 is enough (Up To replenishment)
DECLARE @Start DATE = DATEADD(DAY, -@StockoutDays, CAST(GETDATE() AS DATE));

DROP TABLE IF EXISTS #ev;
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
                  ORDER BY it.date_created, it.transaction_number) AS next_qty_after,
        it.trans_type
    FROM dbo.inv_tran it
    JOIN dbo.inv_loc il ON il.inv_mast_uid = it.inv_mast_uid AND il.location_id = it.location_id
    WHERE it.date_created >= @Start
      AND it.year_for_period <> 0
      AND il.stockable = 'Y'
      AND (il.inv_max > 0 OR (@RequireMax = 0 AND il.inv_min > 0))   -- not stocked here (max 0, or no min/max for Up To companies): running out is expected
      AND il.company_id = @CompanyId
      AND ISNULL(il.purchase_class, '') <> 'NS'
      AND it.location_id IN (10000,10500,11000,11500,12000,20000,21000,30000,30100,31000,31500,40000,50000,70000,71000)
)
SELECT inv_mast_uid, location_id,
       date_created                                              AS out_start,
       next_date                                                 AS out_end,
       CASE WHEN next_date IS NULL THEN 1 ELSE 0 END             AS ongoing,
       DATEDIFF(DAY, date_created, ISNULL(next_date, GETDATE())) AS days_out
INTO #ev
FROM tx
WHERE qty_after <= 0
  AND (next_qty_after > 0 OR next_date IS NULL)
  AND trans_type IN ('WO', 'IA', 'TR', 'RS', 'UNREC');   -- ran out because stock left, not a zero-qty bookkeeping row
CREATE CLUSTERED INDEX ix_ev ON #ev (inv_mast_uid, location_id);

SELECT
    im.item_id,
    im.item_desc,
    e.location_id,
    CAST(e.out_start AS DATE)                         AS out_start,
    CAST(e.out_end AS DATE)                           AS out_end,
    e.days_out,
    e.ongoing,
    il.purchase_class,
    il.replenishment_method,
    CAST(il.inv_min AS DECIMAL(19,4))                 AS inv_min,
    CAST(il.inv_max AS DECIMAL(19,4))                 AS inv_max,
    CAST(il.safety_stock AS DECIMAL(19,4))            AS safety_stock,
    CAST(il.average_monthly_usage AS DECIMAL(19,4))   AS avg_monthly_usage,
    CAST(il.moving_average_cost AS DECIMAL(19,4))     AS unit_cost,
    il.primary_supplier_id,
    s.supplier_name,
    -- always the supplier's assigned buyer in P21 (including the "Buyer Branch Specific" placeholder), whoever wrote the PO
    COALESCE(NULLIF(LTRIM(RTRIM(ISNULL(sb.first_name, '') + ' ' + ISNULL(sb.last_name, ''))), ''), 'No buyer assigned') AS supplier_buyer,
    pb.po_no                                          AS open_po_no,
    CAST(pb.order_date AS DATE)                       AS open_po_date,
    CAST(pb.due AS DATE)                              AS open_po_due,
    CAST(pb.received_date AS DATE)                    AS open_po_received,
    pa.po_no                                          AS next_po_no,
    CAST(pa.order_date AS DATE)                       AS next_po_date
FROM #ev e
JOIN dbo.inv_mast im ON im.inv_mast_uid = e.inv_mast_uid
JOIN dbo.inv_loc  il ON il.inv_mast_uid = e.inv_mast_uid AND il.location_id = e.location_id
LEFT JOIN dbo.supplier s  ON s.supplier_id = il.primary_supplier_id
LEFT JOIN dbo.contacts sb ON sb.id = s.buyer_id
OUTER APPLY (
    SELECT TOP 1 ph.po_no, ph.order_date, COALESCE(pl.date_due, ph.expected_date, ph.date_due) AS due, pl.received_date
    FROM dbo.po_line pl
    JOIN dbo.po_hdr ph ON ph.po_no = pl.po_no
    WHERE pl.inv_mast_uid = e.inv_mast_uid
      AND ph.location_id  = e.location_id
      AND ph.order_date  <= e.out_start
      AND (pl.received_date IS NULL OR pl.received_date >= CAST(e.out_start AS DATE))
      AND ph.delete_flag = 'N' AND pl.delete_flag = 'N' AND pl.cancel_flag = 'N'
    ORDER BY ph.order_date DESC
) pb
OUTER APPLY (
    SELECT TOP 1 ph.po_no, ph.order_date
    FROM dbo.po_line pl
    JOIN dbo.po_hdr ph ON ph.po_no = pl.po_no
    WHERE pl.inv_mast_uid = e.inv_mast_uid
      AND ph.location_id  = e.location_id
      AND ph.order_date   > e.out_start
      AND ph.delete_flag = 'N' AND pl.delete_flag = 'N' AND pl.cancel_flag = 'N'
    ORDER BY ph.order_date ASC
) pa;
