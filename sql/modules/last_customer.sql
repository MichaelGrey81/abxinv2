/* ============================================
   WHO TO SELL SLOW AND DEAD STOCK BACK TO  (module: last_customer)
   Based on: Dead Stock Last Customer, Dead Stock Sales History
   For every item-location holding open FIFO stock that hasn't sold in
   @SlowDays: the last customer who bought it at that location, and the
   top customer for the item anywhere in the last 12 months.
   ============================================ */
SET NOCOUNT ON;
DECLARE @CompanyId INT = 1;
DECLARE @SlowDays  INT = 180;

DROP TABLE IF EXISTS #tgt;
SELECT DISTINCT fl.inv_mast_uid, fl.location_id
INTO #tgt
FROM dbo.fifo_layers fl
JOIN dbo.p21_item_location_view pv
  ON pv.inv_mast_uid = fl.inv_mast_uid AND pv.location_id = fl.location_id
WHERE fl.complete = 'N'
  AND fl.fifo_layer_qty > 0
  AND pv.company_id = @CompanyId
  AND pv.primary_supplier = 'Y'
  AND (pv.last_sale_date IS NULL OR pv.last_sale_date < DATEADD(DAY, -@SlowDays, GETDATE()));
CREATE CLUSTERED INDEX ix_tgt ON #tgt (inv_mast_uid, location_id);

;WITH last_here AS (
    SELECT sh.inv_mast_uid, sh.sales_location_id, sh.customer_id, sh.customer_name, sh.invoice_date,
           ROW_NUMBER() OVER (PARTITION BY sh.inv_mast_uid, sh.sales_location_id
                              ORDER BY sh.invoice_date DESC, sh.invoice_no DESC) AS rn
    FROM dbo.p21_sales_history_aba_view sh
    JOIN #tgt t ON t.inv_mast_uid = sh.inv_mast_uid AND t.location_id = sh.sales_location_id
    WHERE sh.qty_shipped > 0
),
top_anywhere AS (
    SELECT inv_mast_uid, customer_id, customer_name, sales_location_id, qty,
           ROW_NUMBER() OVER (PARTITION BY inv_mast_uid ORDER BY qty DESC) AS rn
    FROM (
        SELECT sh.inv_mast_uid, sh.customer_id, MAX(sh.customer_name) AS customer_name,
               MAX(sh.sales_location_id) AS sales_location_id, SUM(sh.qty_shipped) AS qty
        FROM dbo.p21_sales_history_aba_view sh
        WHERE sh.invoice_date >= DATEADD(MONTH, -12, GETDATE())
          AND sh.company_id = @CompanyId
          AND sh.qty_shipped > 0
          AND sh.inv_mast_uid IN (SELECT inv_mast_uid FROM #tgt)
        GROUP BY sh.inv_mast_uid, sh.customer_id
    ) x
)
SELECT
    im.item_id,
    t.location_id,
    lh.customer_id                     AS last_customer_id,
    lh.customer_name                   AS last_customer_name,
    CAST(lh.invoice_date AS DATE)      AS last_customer_date,
    ta.customer_id                     AS top_customer_12m_id,
    ta.customer_name                   AS top_customer_12m_name,
    ta.sales_location_id               AS top_customer_12m_location,
    CAST(ta.qty AS DECIMAL(19,4))      AS top_customer_12m_qty
FROM #tgt t
JOIN dbo.inv_mast im ON im.inv_mast_uid = t.inv_mast_uid
LEFT JOIN last_here    lh ON lh.inv_mast_uid = t.inv_mast_uid AND lh.sales_location_id = t.location_id AND lh.rn = 1
LEFT JOIN top_anywhere ta ON ta.inv_mast_uid = t.inv_mast_uid AND ta.rn = 1
WHERE lh.customer_id IS NOT NULL OR ta.customer_id IS NOT NULL;
