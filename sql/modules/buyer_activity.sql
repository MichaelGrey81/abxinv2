/* ============================================
   PO ACTIVITY BY BUYER  (module: buyer_activity)
   Based on: PO by Buyer, Last PO Date by Buyer, PO Changed by Someone
   Other than Buyer, Number of POs Not Received by Warehouse on Time.
   Branch POs entered in the last @BuyerDays (corp DCs and consignment
   locations are left out), one row per PO buyer (the PO's
   requested-by contact, the same name the rest of the dashboard uses).
   Lines are judged on time once they are fully received or past due:
   on time = received in full by the line's due date.
   price_overrides counts lines where the PO price was edited by hand,
   keyed_by_other counts POs entered by a different user than the buyer.
   ============================================ */
SET NOCOUNT ON;
DECLARE @CompanyId INT = 1;
DECLARE @BuyerDays INT = 180;
DECLARE @Start DATE = DATEADD(DAY, -@BuyerDays, CAST(GETDATE() AS DATE));
DECLARE @Today DATE = CAST(GETDATE() AS DATE);

DROP TABLE IF EXISTS #pl;

SELECT ph.po_no, pl.line_no, ph.supplier_id, ph.location_id, ph.po_type,
       COALESCE(NULLIF(LTRIM(RTRIM(ISNULL(c.first_name, '') + ' ' + ISNULL(c.last_name, ''))), ''), '(no requester)') AS buyer,
       CASE WHEN u.contact_id IS NOT NULL AND u.contact_id <> ph.requested_by THEN 1 ELSE 0 END AS keyed_by_other,
       CAST(ph.order_date AS DATE) AS order_date,
       CAST(COALESCE(pl.date_due, ph.expected_date, ph.date_due) AS DATE) AS due,
       CAST(pl.received_date AS DATE) AS received,
       pl.qty_ordered, pl.qty_received, pl.cancel_flag,
       CAST(pl.qty_ordered * pl.unit_price / NULLIF(pl.pricing_unit_size, 0) AS DECIMAL(19,2)) AS value,
       CASE WHEN pl.price_edit = 'Y' THEN 1 ELSE 0 END AS price_edit,
       CASE WHEN pl.quantity_changed = 'Y' THEN 1 ELSE 0 END AS qty_changed,
       CASE WHEN pl.expedite_flag = 'Y' OR ph.expedite_flag = 'Y' THEN 1 ELSE 0 END AS expedite,
       CASE WHEN il.stockable = 'Y' AND il.inv_max > 0 AND ISNULL(il.purchase_class, '') <> 'NS' THEN 1 ELSE 0 END AS stocked
INTO #pl
FROM dbo.po_line pl
JOIN dbo.po_hdr ph       ON ph.po_no = pl.po_no
LEFT JOIN dbo.contacts c ON c.id = ph.requested_by
LEFT JOIN dbo.users u    ON u.id = ph.created_by
LEFT JOIN dbo.inv_loc il ON il.inv_mast_uid = pl.inv_mast_uid AND il.location_id = ph.location_id
WHERE ph.company_no = @CompanyId
  AND ph.location_id IN (10000,10500,11000,11500,12000,20000,21000,30000,30100,31000,31500,40000,50000,70000,71000)   -- branches only: corp DCs and consignment are left out
  AND ph.order_date >= @Start
  AND ph.delete_flag = 'N' AND pl.delete_flag = 'N'
  AND pl.qty_ordered > 0;

SELECT
    buyer,
    COUNT(DISTINCT po_no)                                                        AS pos,
    COUNT(*)                                                                     AS po_lines,
    SUM(CASE WHEN cancel_flag = 'Y' THEN 1 ELSE 0 END)                           AS lines_canceled,
    CAST(SUM(CASE WHEN cancel_flag = 'Y' THEN 0 ELSE value END) AS DECIMAL(19,2)) AS po_value,
    COUNT(DISTINCT supplier_id)                                                  AS suppliers,
    COUNT(DISTINCT location_id)                                                  AS locations,
    SUM(stocked)                                                                 AS stock_lines,
    COUNT(DISTINCT CASE WHEN po_type = 'D' THEN po_no END)                       AS direct_pos,
    SUM(CASE WHEN cancel_flag <> 'Y' AND (qty_received >= qty_ordered OR due < @Today) THEN 1 ELSE 0 END) AS lines_judged,
    SUM(CASE WHEN cancel_flag <> 'Y' AND qty_received >= qty_ordered AND received <= due THEN 1 ELSE 0 END) AS lines_on_time,
    CAST(AVG(CASE WHEN cancel_flag <> 'Y' AND qty_received >= qty_ordered AND received IS NOT NULL
                  THEN DATEDIFF(DAY, order_date, received) * 1.0 END) AS DECIMAL(9,1)) AS avg_lead_days,
    SUM(price_edit)                                                              AS price_overrides,
    SUM(qty_changed)                                                             AS qty_changed_lines,
    SUM(expedite)                                                                AS expedited_lines,
    COUNT(DISTINCT CASE WHEN keyed_by_other = 1 THEN po_no END)                  AS keyed_by_other,
    CAST(MAX(order_date) AS DATE)                                                AS last_po_date,
    COUNT(DISTINCT order_date)                                                   AS days_with_pos
FROM #pl
GROUP BY buyer;
