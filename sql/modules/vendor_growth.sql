/* ============================================
   VENDOR GROWTH  (module: vendor_growth)
   Monthly purchases (PO receipts, extended receipt cost) and sales / COGS
   (sales history, by the supplier on the invoice line) per supplier for the
   last @GrowthMonths full months plus the current month to date.
   The vendor scorecard compares the last 12 full months with the 12 before,
   and the last 3 full months with the same 3 months a year earlier.
   ============================================ */
SET NOCOUNT ON;
DECLARE @CompanyId    INT = 1;
DECLARE @GrowthMonths INT = 24;
DECLARE @Start DATE = DATEADD(MONTH, -@GrowthMonths, DATEFROMPARTS(YEAR(GETDATE()), MONTH(GETDATE()), 1));

;WITH rec AS (
    SELECT ph.supplier_id,
           DATEFROMPARTS(YEAR(irh.date_created), MONTH(irh.date_created), 1) AS month,
           SUM(irl.extended_cost)                                             AS purchases,
           COUNT(DISTINCT irh.receipt_number)                                 AS receipts
    FROM dbo.inventory_receipts_hdr irh
    JOIN dbo.inventory_receipts_line irl ON irl.receipt_number = irh.receipt_number
    JOIN dbo.po_hdr ph ON ph.po_no = irh.po_number
    WHERE irh.date_created >= @Start
      AND ISNULL(irh.delete_flag, 'N') = 'N'
      AND ph.company_no = @CompanyId
    GROUP BY ph.supplier_id, DATEFROMPARTS(YEAR(irh.date_created), MONTH(irh.date_created), 1)
),
sal AS (
    SELECT sh.supplier_id,
           DATEFROMPARTS(YEAR(sh.invoice_date), MONTH(sh.invoice_date), 1)    AS month,
           SUM(sh.sales_price)                                                AS sales,
           SUM(sh.cogs_amount)                                                AS cogs
    FROM dbo.p21_sales_history_aba_view sh
    WHERE sh.invoice_date >= @Start
      AND sh.company_id = @CompanyId
      AND ISNULL(sh.other_charge_item, 'N') <> 'Y'
      AND sh.supplier_id IS NOT NULL
    GROUP BY sh.supplier_id, DATEFROMPARTS(YEAR(sh.invoice_date), MONTH(sh.invoice_date), 1)
)
SELECT
    COALESCE(r.supplier_id, s.supplier_id)            AS supplier_id,
    sp.supplier_name,
    CAST(COALESCE(r.month, s.month) AS DATE)          AS month,
    CAST(ISNULL(r.purchases, 0) AS DECIMAL(19,2))     AS purchases,
    ISNULL(r.receipts, 0)                             AS receipts,
    CAST(ISNULL(s.sales, 0) AS DECIMAL(19,2))         AS sales,
    CAST(ISNULL(s.cogs, 0) AS DECIMAL(19,2))          AS cogs
FROM rec r
FULL JOIN sal s ON s.supplier_id = r.supplier_id AND s.month = r.month
LEFT JOIN dbo.supplier sp ON sp.supplier_id = COALESCE(r.supplier_id, s.supplier_id);
