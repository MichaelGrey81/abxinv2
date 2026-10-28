/* ============================================
   AUTO-BUY CANDIDATES  (module: autobuy_vendors)
   POs entered in the last @AutoDays at every location (branches, DCs and
   consignment; the screen can split them), one row per supplier, location
   and PO buyer (requested-by contact), with what makes a supplier easy or
   hard to hand to an automated buyer (requirement -> PO placed and
   confirmed with no one touching it):
     - freight: the branch's prepaid-freight target in location_supplier
       (0 = no threshold, any size PO ships) and the PO minimum (target_value)
     - how POs reach the supplier: EDI (can be acknowledged automatically),
       email, fax or print, from supplier
     - how often people touch the POs: price edits, quantity changes,
       expedites, cancels, and lines tied to customer orders or direct ship
     - whether lines are for stocked items (replenishment, not one-offs)
     - delivery: on time, and lead-time spread (n, sum and sum of squares
       of days from order to receipt, so the screen can work out a spread)
   ============================================ */
SET NOCOUNT ON;
DECLARE @CompanyId INT = 1;
DECLARE @AutoDays INT = 365;
DECLARE @Start DATE = DATEADD(DAY, -@AutoDays, CAST(GETDATE() AS DATE));
DECLARE @Today DATE = CAST(GETDATE() AS DATE);

DROP TABLE IF EXISTS #ab;

SELECT ph.po_no, ph.supplier_id, ph.location_id, ph.po_type,
       COALESCE(NULLIF(LTRIM(RTRIM(ISNULL(c.first_name, '') + ' ' + ISNULL(c.last_name, ''))), ''), '(no requester)') AS buyer,
       CAST(ph.order_date AS DATE) AS order_date,
       CAST(COALESCE(pl.date_due, ph.expected_date, ph.date_due) AS DATE) AS due,
       CAST(pl.received_date AS DATE) AS received,
       pl.qty_ordered, pl.qty_received, pl.cancel_flag,
       CAST(pl.qty_ordered * pl.unit_price / NULLIF(pl.pricing_unit_size, 0) AS DECIMAL(19,2)) AS value,
       CASE WHEN pl.price_edit = 'Y' THEN 1 ELSE 0 END AS price_edit,
       CASE WHEN pl.quantity_changed = 'Y' THEN 1 ELSE 0 END AS qty_changed,
       CASE WHEN pl.expedite_flag = 'Y' OR ph.expedite_flag = 'Y' THEN 1 ELSE 0 END AS expedite,
       CASE WHEN il.stockable = 'Y' AND il.inv_max > 0 AND ISNULL(il.purchase_class, '') <> 'NS' THEN 1 ELSE 0 END AS stocked,
       CASE WHEN ph.po_type = 'D' OR EXISTS (SELECT 1 FROM dbo.oe_line_po x WHERE x.po_no = pl.po_no AND x.po_line_number = pl.line_no AND x.delete_flag = 'N') THEN 1 ELSE 0 END AS for_order
INTO #ab
FROM dbo.po_line pl
JOIN dbo.po_hdr ph       ON ph.po_no = pl.po_no
LEFT JOIN dbo.contacts c ON c.id = ph.requested_by
LEFT JOIN dbo.inv_loc il ON il.inv_mast_uid = pl.inv_mast_uid AND il.location_id = ph.location_id
WHERE ph.company_no = @CompanyId
  AND ph.location_id IN (SELECT location_id FROM dbo.location WHERE company_id = @CompanyId)   -- every location: DC buying is part of the team's workload
  AND ph.order_date >= @Start
  AND ph.delete_flag = 'N' AND pl.delete_flag = 'N'
  AND pl.qty_ordered > 0;

SELECT
    a.supplier_id,
    MAX(s.supplier_name)                                                          AS supplier_name,
    a.location_id,
    a.buyer,
    MAX(COALESCE(NULLIF(LTRIM(RTRIM(ISNULL(sb.first_name, '') + ' ' + ISNULL(sb.last_name, ''))), ''), '')) AS supplier_buyer,
    COUNT(DISTINCT CASE WHEN a.cancel_flag <> 'Y' THEN a.po_no END)               AS pos,
    SUM(CASE WHEN a.cancel_flag <> 'Y' THEN 1 ELSE 0 END)                         AS po_lines,
    CAST(SUM(CASE WHEN a.cancel_flag <> 'Y' THEN a.value ELSE 0 END) AS DECIMAL(19,2)) AS po_value,
    SUM(CASE WHEN a.cancel_flag = 'Y' THEN 1 ELSE 0 END)                          AS lines_canceled,
    SUM(CASE WHEN a.cancel_flag <> 'Y' THEN a.stocked ELSE 0 END)                 AS stock_lines,
    SUM(CASE WHEN a.cancel_flag <> 'Y' THEN a.for_order ELSE 0 END)               AS order_lines,
    SUM(a.price_edit)                                                             AS price_edits,
    SUM(a.qty_changed)                                                            AS qty_changes,
    SUM(a.expedite)                                                               AS expedites,
    SUM(CASE WHEN a.cancel_flag <> 'Y' AND (a.qty_received >= a.qty_ordered OR a.due < @Today) THEN 1 ELSE 0 END) AS lines_judged,
    SUM(CASE WHEN a.cancel_flag <> 'Y' AND a.qty_received >= a.qty_ordered AND a.received <= a.due THEN 1 ELSE 0 END) AS lines_on_time,
    SUM(CASE WHEN a.cancel_flag <> 'Y' AND a.qty_received >= a.qty_ordered AND a.received IS NOT NULL THEN 1 ELSE 0 END) AS lead_n,
    SUM(CASE WHEN a.cancel_flag <> 'Y' AND a.qty_received >= a.qty_ordered AND a.received IS NOT NULL THEN DATEDIFF(DAY, a.order_date, a.received) ELSE 0 END) AS lead_sum,
    SUM(CASE WHEN a.cancel_flag <> 'Y' AND a.qty_received >= a.qty_ordered AND a.received IS NOT NULL THEN CAST(DATEDIFF(DAY, a.order_date, a.received) AS BIGINT) * DATEDIFF(DAY, a.order_date, a.received) ELSE 0 END) AS lead_sumsq,
    MAX(ls.freight_control_value)                                                 AS freight_control,
    MAX(TRY_CAST(ls.freight_target_value AS DECIMAL(19,2)))                       AS freight_target,
    MAX(ls.control_value)                                                         AS min_control,
    MAX(TRY_CAST(ls.target_value AS DECIMAL(19,2)))                               AS min_target,
    MAX(ls.review_cycle)                                                          AS review_cycle,
    MAX(s.edi_po_flag)                                                            AS edi_po,
    MAX(s.email_po_flag)                                                          AS email_po,
    MAX(s.fax_po_flag)                                                            AS fax_po,
    MAX(s.po_default_method)                                                      AS po_method,
    MAX(TRY_CAST(s.minimum_process_po_cost AS DECIMAL(19,2)))                     AS min_po_cost
FROM #ab a
JOIN dbo.supplier s                ON s.supplier_id = a.supplier_id
LEFT JOIN dbo.contacts sb          ON sb.id = s.buyer_id
LEFT JOIN dbo.location_supplier ls ON ls.supplier_id = a.supplier_id AND ls.location_id = a.location_id
GROUP BY a.supplier_id, a.location_id, a.buyer;
