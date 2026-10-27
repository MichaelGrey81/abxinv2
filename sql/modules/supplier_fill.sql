/* ============================================
   SUPPLIER FILL RATE  (module: supplier_fill)
   Based on: Fill Rate (a PO is a "hit" when it arrives in one receipt).
   PO lines for stocked items on POs entered in the last @SupplierFillDays
   days, judged once they are fully received or past due. Per line:
     - filled on first receipt: the first receipt covered the full quantity
     - on time: the first receipt came on or before the line's due date
     - on time in full (OTIF): the full quantity was received by the due date
   Per PO: received in a single receipt (the saved query's "hit").
   Quantities are compared in stocking units (qty x unit_size).
   One row per supplier and PO location.
   ============================================ */
SET NOCOUNT ON;
DECLARE @CompanyId        INT = 1;
DECLARE @RequireMax       INT = 1;
DECLARE @SupplierFillDays INT = 180;
DECLARE @Start DATE = DATEADD(DAY, -@SupplierFillDays, CAST(GETDATE() AS DATE));
DECLARE @Today DATE = CAST(GETDATE() AS DATE);

DROP TABLE IF EXISTS #pl, #pr, #px;

SELECT ph.po_no, pl.line_no, ph.supplier_id, ph.location_id,
       CAST(COALESCE(pl.date_due, ph.expected_date, ph.date_due) AS DATE) AS due,
       CAST(pl.qty_ordered * ISNULL(NULLIF(pl.unit_size, 0), 1) AS DECIMAL(19,4))  AS qty,
       CAST(pl.qty_received * ISNULL(NULLIF(pl.unit_size, 0), 1) AS DECIMAL(19,4)) AS qty_received,
       CAST(pl.qty_ordered * pl.unit_price / NULLIF(pl.pricing_unit_size, 0) AS DECIMAL(19,2)) AS value
INTO #pl
FROM dbo.po_line pl
JOIN dbo.po_hdr  ph ON ph.po_no = pl.po_no
JOIN dbo.inv_loc il ON il.inv_mast_uid = pl.inv_mast_uid AND il.location_id = ph.location_id
WHERE ph.company_no = @CompanyId
  AND ph.order_date >= @Start
  AND ph.delete_flag = 'N' AND pl.delete_flag = 'N' AND pl.cancel_flag = 'N'
  AND pl.qty_ordered > 0
  AND il.stockable = 'Y'
  AND (il.inv_max > 0 OR (@RequireMax = 0 AND il.inv_min > 0))
  AND ISNULL(il.purchase_class, '') <> 'NS'
  AND (pl.qty_received >= pl.qty_ordered OR COALESCE(pl.date_due, ph.expected_date, ph.date_due) < @Today);   -- judged: complete or past due
CREATE CLUSTERED INDEX ix_pl ON #pl (po_no, line_no);

-- receipts against those lines, in stocking units
SELECT irh.po_number AS po_no, irl.po_line_number AS line_no, irh.receipt_number, CAST(irh.date_created AS DATE) AS received,
       CAST(irl.qty_received * ISNULL(NULLIF(irl.unit_size, 0), 1) AS DECIMAL(19,4)) AS q
INTO #pr
FROM dbo.inventory_receipts_hdr irh
JOIN dbo.inventory_receipts_line irl ON irl.receipt_number = irh.receipt_number
WHERE ISNULL(irh.delete_flag, 'N') = 'N'
  AND irl.qty_received > 0
  AND irh.po_number IN (SELECT DISTINCT po_no FROM #pl);
CREATE CLUSTERED INDEX ix_pr ON #pr (po_no, line_no, received);

SELECT l.*, f.first_dt, ISNULL(f1.q, 0) AS q_first, ISNULL(bd.q, 0) AS q_by_due, ISNULL(n.receipts, 0) AS receipts
INTO #px
FROM #pl l
OUTER APPLY (SELECT MIN(r.received) first_dt FROM #pr r WHERE r.po_no = l.po_no AND r.line_no = l.line_no) f
OUTER APPLY (SELECT SUM(r.q) q FROM #pr r WHERE r.po_no = l.po_no AND r.line_no = l.line_no AND r.received = f.first_dt) f1
OUTER APPLY (SELECT SUM(r.q) q FROM #pr r WHERE r.po_no = l.po_no AND r.line_no = l.line_no AND r.received <= l.due) bd
OUTER APPLY (SELECT COUNT(DISTINCT r.receipt_number) receipts FROM #pr r WHERE r.po_no = l.po_no AND r.line_no = l.line_no) n;

;WITH po AS (
    SELECT po_no, supplier_id, location_id, COUNT(DISTINCT r.receipt_number) AS receipts
    FROM #px x OUTER APPLY (SELECT r.receipt_number FROM #pr r WHERE r.po_no = x.po_no) r
    GROUP BY po_no, supplier_id, location_id
)
SELECT
    x.supplier_id,
    s.supplier_name,
    x.location_id,
    COALESCE(NULLIF(LTRIM(RTRIM(ISNULL(c.first_name, '') + ' ' + ISNULL(c.last_name, ''))), ''), 'No buyer assigned') AS supplier_buyer,
    COUNT(*)                                                                         AS lines,
    SUM(CASE WHEN x.first_dt IS NOT NULL AND x.q_first >= x.qty - 0.0001 THEN 1 ELSE 0 END) AS lines_full_first,
    SUM(CASE WHEN x.first_dt IS NOT NULL AND x.first_dt <= x.due THEN 1 ELSE 0 END)  AS lines_on_time,
    SUM(CASE WHEN x.q_by_due >= x.qty - 0.0001 THEN 1 ELSE 0 END)                    AS lines_otif,
    SUM(CASE WHEN x.first_dt IS NULL THEN 1 ELSE 0 END)                              AS lines_not_received,
    CAST(SUM(x.qty) AS DECIMAL(19,2))                                                AS qty_ordered,
    CAST(SUM(CASE WHEN x.q_by_due > x.qty THEN x.qty ELSE x.q_by_due END) AS DECIMAL(19,2)) AS qty_by_due,
    CAST(SUM(x.value) AS DECIMAL(19,2))                                              AS value_ordered,
    CAST(AVG(CASE WHEN x.first_dt > x.due THEN DATEDIFF(DAY, x.due, x.first_dt) * 1.0 END) AS DECIMAL(9,1)) AS avg_days_late,
    (SELECT COUNT(*) FROM po p WHERE p.supplier_id = x.supplier_id AND p.location_id = x.location_id)                      AS pos,
    (SELECT COUNT(*) FROM po p WHERE p.supplier_id = x.supplier_id AND p.location_id = x.location_id AND p.receipts = 1)   AS pos_one_receipt
FROM #px x
LEFT JOIN dbo.supplier s ON s.supplier_id = x.supplier_id
LEFT JOIN dbo.contacts c ON c.id = s.buyer_id
GROUP BY x.supplier_id, s.supplier_name, x.location_id, c.first_name, c.last_name;
