/* ============================================
   CURRENT CUSTOMER BACKORDERS  (module: backorders)
   Based on: Critical Item Not on PO - P Team report, CNOPO
   One row per item-location with customer backorders, with on-hand,
   in-transit, buyer and the age of the oldest open backorder line.
   The dashboard checks other branches' free stock to suggest transfers
   that would clear the backorder.
   ============================================ */
SET NOCOUNT ON;
DECLARE @CompanyId INT = 1;

;WITH bo AS (
    SELECT ol.inv_mast_uid, ol.source_loc_id,
           COUNT(*)                              AS open_lines,
           COUNT(DISTINCT ol.order_no)           AS open_orders,
           MIN(CAST(ol.date_created AS DATE))    AS oldest_bo_date
    FROM dbo.oe_line ol
    JOIN dbo.oe_hdr oh ON oh.order_no = ol.order_no
    WHERE ol.complete = 'N'
      AND ol.disposition = 'B'
      AND oh.approved = 'Y'
      AND ISNULL(ol.delete_flag, 'N') = 'N'
      AND ISNULL(ol.cancel_flag, 'N') = 'N'
    GROUP BY ol.inv_mast_uid, ol.source_loc_id
)
SELECT
    im.item_id,
    im.item_desc,
    il.location_id,
    il.purchase_class,
    il.stockable,
    CAST(il.qty_on_hand     AS DECIMAL(19,4))  AS qty_on_hand,
    CAST(il.qty_allocated   AS DECIMAL(19,4))  AS qty_allocated,
    CAST(il.qty_backordered AS DECIMAL(19,4))  AS qty_backordered,
    CAST(il.qty_in_transit  AS DECIMAL(19,4))  AS qty_in_transit,
    CAST(il.order_quantity  AS DECIMAL(19,4))  AS qty_on_po,
    il.primary_supplier_id,
    s.supplier_name,
    LTRIM(RTRIM(ISNULL(c.first_name, '') + ' ' + ISNULL(c.last_name, ''))) AS buyer,
    bo.open_lines,
    bo.open_orders,
    bo.oldest_bo_date,
    DATEDIFF(DAY, bo.oldest_bo_date, GETDATE()) AS oldest_bo_days,
    CAST(il.moving_average_cost AS DECIMAL(19,4)) AS unit_cost
FROM dbo.inv_loc il
JOIN dbo.inv_mast im ON im.inv_mast_uid = il.inv_mast_uid
LEFT JOIN bo ON bo.inv_mast_uid = il.inv_mast_uid AND bo.source_loc_id = il.location_id
LEFT JOIN dbo.supplier s ON s.supplier_id = il.primary_supplier_id
LEFT JOIN dbo.contacts c ON c.id = s.buyer_id
WHERE il.qty_backordered > 0
  AND il.company_id = @CompanyId
  AND ISNULL(il.delete_flag, 'N') = 'N';
