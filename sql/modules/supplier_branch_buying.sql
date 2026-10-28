/* ============================================
   PURCHASING BY SUPPLIER, BRANCH AND WRITER  (module: supplier_branch_buying)
   Branch POs entered in the last @BuyerDays, one row per supplier, branch
   and PO buyer (requested-by contact), plus the supplier's assigned buyer.
   The buyer structure screen uses it to tell national suppliers (bought by
   all or nearly all branches) from regional ones, size each role's
   workload, and see who already knows which suppliers and branches.
   ============================================ */
SET NOCOUNT ON;
DECLARE @CompanyId INT = 1;
DECLARE @BuyerDays INT = 180;
DECLARE @Start DATE = DATEADD(DAY, -@BuyerDays, CAST(GETDATE() AS DATE));
DECLARE @Today DATE = CAST(GETDATE() AS DATE);

SELECT
    ph.supplier_id,
    MAX(s.supplier_name)                                                        AS supplier_name,
    ph.location_id,
    COALESCE(NULLIF(LTRIM(RTRIM(ISNULL(c.first_name, '') + ' ' + ISNULL(c.last_name, ''))), ''), '(no requester)') AS buyer,
    MAX(COALESCE(NULLIF(LTRIM(RTRIM(ISNULL(sb.first_name, '') + ' ' + ISNULL(sb.last_name, ''))), ''), '')) AS supplier_buyer,
    COUNT(DISTINCT ph.po_no)                                                    AS pos,
    COUNT(*)                                                                    AS po_lines,
    CAST(SUM(pl.qty_ordered * pl.unit_price / NULLIF(pl.pricing_unit_size, 0)) AS DECIMAL(19,2)) AS po_value,
    SUM(CASE WHEN pl.qty_received >= pl.qty_ordered OR CAST(COALESCE(pl.date_due, ph.expected_date, ph.date_due) AS DATE) < @Today THEN 1 ELSE 0 END) AS lines_judged,
    SUM(CASE WHEN pl.qty_received >= pl.qty_ordered AND CAST(pl.received_date AS DATE) <= CAST(COALESCE(pl.date_due, ph.expected_date, ph.date_due) AS DATE) THEN 1 ELSE 0 END) AS lines_on_time
FROM dbo.po_line pl
JOIN dbo.po_hdr ph        ON ph.po_no = pl.po_no
JOIN dbo.supplier s       ON s.supplier_id = ph.supplier_id
LEFT JOIN dbo.contacts c  ON c.id = ph.requested_by
LEFT JOIN dbo.contacts sb ON sb.id = s.buyer_id
WHERE ph.company_no = @CompanyId
  AND ph.location_id IN (10000,10500,11000,11500,12000,20000,21000,30000,30100,31000,31500,40000,50000,70000,71000)
  AND ph.order_date >= @Start
  AND ph.delete_flag = 'N' AND pl.delete_flag = 'N' AND pl.cancel_flag = 'N'
  AND pl.qty_ordered > 0
GROUP BY ph.supplier_id, ph.location_id,
         COALESCE(NULLIF(LTRIM(RTRIM(ISNULL(c.first_name, '') + ' ' + ISNULL(c.last_name, ''))), ''), '(no requester)');
