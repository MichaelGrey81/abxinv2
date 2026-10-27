/* ============================================
   STOCK STILL INSIDE THE SUPPLIER RETURN WINDOW  (module: return_window)
   Based on: Digest1 (Tier 1 return-eligible), Return Script v5
   Open FIFO layers received on a PO whose supplier return window
   (abix_supplier_return_policies.timeframe_in_days) has not expired.
   The dashboard keeps the ones whose item-location is dead or slow and
   sorts by days left, so returns go out before the window closes.
   ============================================ */
SET NOCOUNT ON;
DECLARE @CompanyId INT = 1;
DECLARE @Today DATE = CAST(GETDATE() AS DATE);

;WITH rp AS (
    SELECT supplier_id, MAX(timeframe_in_days) AS return_days, MAX(restock_percent) AS restock_percent,
           MAX(CAST(return_policy AS NVARCHAR(400))) AS return_policy
    FROM dbo.abix_supplier_return_policies
    WHERE timeframe_in_days > 0
    GROUP BY supplier_id
)
SELECT
    im.item_id,
    fl.location_id,
    fl.document_no                                               AS receipt_no,
    ph.po_no,
    CAST(fl.date_received AS DATE)                               AS date_received,
    CAST(fl.fifo_layer_qty AS DECIMAL(19,4))                     AS qty,
    CAST(fl.fifo_layer_qty * fl.cost AS DECIMAL(19,2))           AS value,
    ph.supplier_id,
    s.supplier_name,
    LTRIM(RTRIM(ISNULL(c.first_name, '') + ' ' + ISNULL(c.last_name, ''))) AS po_buyer,
    rp.return_days,
    CAST(CASE WHEN rp.restock_percent > 1 THEN rp.restock_percent / 100.0 ELSE rp.restock_percent END AS DECIMAL(9,4)) AS restock_rate,
    rp.return_policy,
    CAST(DATEADD(DAY, rp.return_days, fl.date_received) AS DATE) AS return_by,
    DATEDIFF(DAY, @Today, DATEADD(DAY, rp.return_days, fl.date_received)) AS days_left
FROM dbo.fifo_layers fl
JOIN dbo.inv_mast im              ON im.inv_mast_uid = fl.inv_mast_uid
JOIN dbo.inventory_receipts_hdr irh ON irh.receipt_number = fl.document_no
JOIN dbo.po_hdr ph                ON ph.po_no = irh.po_number
JOIN rp                           ON rp.supplier_id = ph.supplier_id
LEFT JOIN dbo.supplier s          ON s.supplier_id = ph.supplier_id
LEFT JOIN dbo.contacts c          ON c.id = ph.requested_by
WHERE fl.complete = 'N'
  AND fl.fifo_layer_qty > 0
  AND fl.journal = 'IR'
  AND fl.company_id = @CompanyId
  AND DATEADD(DAY, rp.return_days, fl.date_received) >= @Today;
