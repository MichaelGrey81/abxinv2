/* ============================================
   OPEN PO LINES  (module: open_po)
   Based on: Open PO Tracker, Live Inbound Good Tracker, PO History with Dates
   One row per open PO line. The dashboard matches it to on-hand stock by
   item + location to flag stock on order for items that are already dead,
   slow, over max or past due.
   Quantities are in stocking units (same as FIFO qty). Value uses
   unit_price / pricing_unit_size, as in PO History with Dates.
   ============================================ */
SET NOCOUNT ON;
DECLARE @CompanyId INT = 1;

SELECT
    pl.po_no,
    pl.line_no,
    ph.location_id,
    im.item_id,
    im.item_desc,
    ph.supplier_id,
    s.supplier_name,
    LTRIM(RTRIM(ISNULL(c.first_name, '') + ' ' + ISNULL(c.last_name, '')))           AS buyer,
    CAST(ph.order_date AS DATE)                                                      AS po_date,
    CAST(COALESCE(pl.date_due, ph.expected_date, ph.date_due) AS DATE)               AS date_due,
    CAST(pl.qty_ordered - pl.qty_received AS DECIMAL(19,4))                          AS qty_open,
    CAST(pl.unit_price / NULLIF(pl.pricing_unit_size, 0) AS DECIMAL(19,4))           AS unit_cost,
    CAST((pl.qty_ordered - pl.qty_received) * pl.unit_price
         / NULLIF(pl.pricing_unit_size, 0) AS DECIMAL(19,2))                         AS value_open,
    DATEDIFF(DAY, COALESCE(pl.date_due, ph.expected_date, ph.date_due), GETDATE())   AS days_past_due,
    ph.po_type,
    ph.sales_order_number
FROM dbo.po_line pl
JOIN dbo.po_hdr  ph ON ph.po_no = pl.po_no
JOIN dbo.inv_mast im ON im.inv_mast_uid = pl.inv_mast_uid
LEFT JOIN dbo.supplier s ON s.supplier_id = ph.supplier_id
LEFT JOIN dbo.contacts c ON c.id = ph.requested_by
WHERE ph.delete_flag = 'N'
  AND pl.delete_flag = 'N'
  AND pl.cancel_flag = 'N'
  AND ISNULL(pl.complete, 'N') <> 'Y'
  AND ISNULL(ph.complete, 'N') <> 'Y'
  AND pl.qty_ordered > pl.qty_received
  AND ph.company_no = @CompanyId;
