/* ============================================
   RECEIPTS BY BUYER, SUPPLIER AND PRICE  (module: receipt_detail)
   PO receipts over the last @ChangeDays, one row per item, location,
   PO requester and supplier, with the average receipt cost in the window
   and the average cost of the same item's receipts in the year before.
   The dashboard splits the receipts rise into price (paying more per
   unit) and volume (buying more units), and credits it to buyers.
   ============================================ */
SET NOCOUNT ON;
DECLARE @CompanyId  INT = 1;
DECLARE @ChangeDays INT = 61;
DECLARE @Now DATETIME = CAST(CAST(GETDATE() AS DATE) AS DATETIME);   -- windows start at midnight
DECLARE @Cur DATETIME = DATEADD(DAY, -@ChangeDays, @Now);

;WITH r AS (
    SELECT it.inv_mast_uid, it.location_id, it.date_created,
           CAST(it.quantity AS DECIMAL(19,4))                    AS qty,
           CAST(it.quantity * it.unit_cost_amt AS DECIMAL(19,4)) AS val,
           ph.supplier_id,
           LTRIM(RTRIM(ISNULL(c.first_name, '') + ' ' + ISNULL(c.last_name, ''))) AS buyer
    FROM dbo.inv_tran it
    JOIN dbo.inventory_receipts_hdr irh ON irh.receipt_number = it.document_no
    JOIN dbo.po_hdr ph                  ON ph.po_no = irh.po_number
    LEFT JOIN dbo.contacts c            ON c.id = ph.requested_by
    WHERE it.trans_type = 'RECPT'
      AND it.date_created >= DATEADD(YEAR, -1, @Cur)
      AND it.location_id IN (SELECT location_id FROM dbo.location WHERE company_id = @CompanyId)
      AND it.quantity > 0
),
prior_cost AS (
    SELECT inv_mast_uid, SUM(val) / NULLIF(SUM(qty), 0) AS prior_unit_cost
    FROM r WHERE date_created < @Cur
    GROUP BY inv_mast_uid
)
SELECT
    im.item_id,
    r.location_id,
    NULLIF(r.buyer, '')                                         AS buyer,
    r.supplier_id,
    s.supplier_name,
    COUNT(*)                                                    AS receipt_lines,
    CAST(SUM(r.qty) AS DECIMAL(19,4))                           AS qty,
    CAST(SUM(r.val) AS DECIMAL(19,2))                           AS value,
    CAST(SUM(r.val) / NULLIF(SUM(r.qty), 0) AS DECIMAL(19,4))   AS unit_cost,
    CAST(MAX(pc.prior_unit_cost) AS DECIMAL(19,4))              AS prior_unit_cost
FROM r
JOIN dbo.inv_mast im     ON im.inv_mast_uid = r.inv_mast_uid
LEFT JOIN prior_cost pc  ON pc.inv_mast_uid = r.inv_mast_uid
LEFT JOIN dbo.supplier s ON s.supplier_id = r.supplier_id
WHERE r.date_created >= @Cur
GROUP BY im.item_id, r.location_id, r.buyer, r.supplier_id, s.supplier_name;
