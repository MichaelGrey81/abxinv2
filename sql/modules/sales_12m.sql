/* ============================================
   SALES, COGS AND GROSS PROFIT, LAST 12 MONTHS  (module: sales_12m)
   Based on: sales_history_for_DB, SalesHistory Analysis
   One row per item + sales location. The dashboard divides COGS by cost
   on hand for turns, and gross profit by cost on hand for GMROI.
   Credits are included so returns net out.
   ============================================ */
SET NOCOUNT ON;
DECLARE @CompanyId   INT = 1;
DECLARE @SalesMonths INT = 12;
DECLARE @Start DATE = DATEADD(MONTH, -@SalesMonths, CAST(GETDATE() AS DATE));

SELECT
    im.item_id,
    sh.sales_location_id                                   AS location_id,
    CAST(SUM(sh.qty_shipped) AS DECIMAL(19,4))             AS qty_sold,
    CAST(SUM(sh.sales_price) AS DECIMAL(19,2))             AS sales,   -- extended line amount
    CAST(SUM(sh.cogs_amount) AS DECIMAL(19,2))             AS cogs,
    COUNT(DISTINCT sh.invoice_no)                          AS invoices,
    COUNT(DISTINCT sh.customer_id)                         AS customers,
    CAST(MAX(sh.invoice_date) AS DATE)                     AS last_invoice_date
FROM dbo.p21_sales_history_aba_view sh
JOIN dbo.inv_mast im ON im.inv_mast_uid = sh.inv_mast_uid
WHERE sh.invoice_date >= @Start
  AND sh.company_id = @CompanyId
  AND ISNULL(sh.other_charge_item, 'N') <> 'Y'
GROUP BY im.item_id, sh.sales_location_id;
