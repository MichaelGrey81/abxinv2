/* ============================================
   AT OR BELOW MIN RIGHT NOW  (module: reorder_now)
   Based on: Critical Item Not on PO, BelowOP, Order Point Script
   Stocked items at the branches (corp DCs and consignment are left out) whose available stock
   (on hand - allocated + in transit + on PO) is at or below the P21 min.
   no_po = 1 means nothing is on order at all: these are the items most
   likely to become the next "not reordered" stockout. Used by the Vendor
   reorder focus screen, together with stockout_events.
   ============================================ */
SET NOCOUNT ON;
DECLARE @CompanyId  INT = 1;
DECLARE @RequireMax INT = 1;

SELECT
    im.item_id,
    im.item_desc,
    il.location_id,
    il.purchase_class,
    il.replenishment_method,
    CAST(il.inv_min AS DECIMAL(19,4))              AS inv_min,
    CAST(il.inv_max AS DECIMAL(19,4))              AS inv_max,
    CAST(il.qty_on_hand AS DECIMAL(19,4))          AS qty_on_hand,
    CAST(il.qty_allocated AS DECIMAL(19,4))        AS qty_allocated,
    CAST(il.qty_backordered AS DECIMAL(19,4))      AS qty_backordered,
    CAST(il.qty_in_transit AS DECIMAL(19,4))       AS qty_in_transit,
    CAST(il.order_quantity AS DECIMAL(19,4))       AS qty_on_po,
    CAST(il.qty_on_hand - il.qty_allocated + il.qty_in_transit + il.order_quantity AS DECIMAL(19,4)) AS qty_available,
    CASE WHEN il.order_quantity <= 0 THEN 1 ELSE 0 END AS no_po,
    CAST(il.moving_average_cost AS DECIMAL(19,4))  AS unit_cost,
    il.primary_supplier_id,
    s.supplier_name,
    -- always the supplier's assigned buyer in P21 (including the "Buyer Branch Specific" placeholder), whoever wrote the PO
    COALESCE(NULLIF(LTRIM(RTRIM(ISNULL(c.first_name, '') + ' ' + ISNULL(c.last_name, ''))), ''), 'No buyer assigned') AS primary_buyer,
    CAST(il.last_sale_date AS DATE)                AS last_sale_date
FROM dbo.inv_loc il
JOIN dbo.inv_mast im      ON im.inv_mast_uid = il.inv_mast_uid
LEFT JOIN dbo.supplier s  ON s.supplier_id = il.primary_supplier_id
LEFT JOIN dbo.contacts c  ON c.id = s.buyer_id
WHERE il.company_id = @CompanyId
  AND ISNULL(il.delete_flag, 'N') = 'N'
  AND il.stockable = 'Y'
  AND ISNULL(il.purchase_class, '') <> 'NS'
  AND il.inv_min > 0
  AND (il.inv_max > 0 OR @RequireMax = 0)
  AND il.location_id IN (10000,10500,11000,11500,12000,20000,21000,30000,30100,31000,31500,40000,50000,70000,71000)
  AND il.qty_on_hand - il.qty_allocated + il.qty_in_transit + il.order_quantity <= il.inv_min;
