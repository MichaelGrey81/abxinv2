/* ============================================
   DEAD / SLOW INVENTORY CLASSIFIER (RECENCY-BASED)
   - Corp locations (100,110,300,500,700,710)  -> CORP
   - Any location not in #locs                  -> CONSIGNMENT
   - Branches                                   -> DEAD / SLOW / AGING / ACTIVE

   Used by inventory_app.py. The app rewrites the values on the
   "DECLARE @Param ... = value;" lines in the Params block below and
   strips GO lines, so this file still runs as-is in SSMS.

   Result sets, in order (the app relies on this order):
     A) Item rollup + usage / days on hand   K) Usage at other locations for DEAD/SLOW items
     B) Top-N by product group (layers)      L) Run info
     C) Top offenders overall (layers)
     D) By product group   E) By supplier   F) By location
     G) Status mix         H) Location + status + stockable
     I) DOH item-level     J) DOH rollup
     M) Open stock by buyer (location x item x PO requester), for "who bought it"

   Buyer attribution: each open FIFO layer from an inventory receipt (journal IR)
   is traced receipt -> PO -> PO requested_by contact. Requesters whose name
   contains a fragment in #purch_buyers count as Purchasing Department,
   other PO requesters as Branch, and non-IR layers as Non-PO/Trace.
   ============================================ */

DROP TABLE IF EXISTS #locs, #purch_buyers, #po_map, #fifo_base, #usageN, #classified, #ranked, #item_rollup, #last_buyer;
GO

SET NOCOUNT ON;

/* ===== Params ===== */
DECLARE @CompanyId        INT = 1;
DECLARE @DeadDays         INT = 365;
DECLARE @SlowDays         INT = 180;
DECLARE @AgingDays        INT = 90;
DECLARE @MinQtyRemaining  DECIMAL(18,4) = 0.0001;
DECLARE @TopN_PerGroup    INT = 5;
DECLARE @TopN_Overall     INT = 25;
DECLARE @UsageMonths      INT = 6;   -- 6 or 12

DECLARE @Today DATE = CAST(GETDATE() AS DATE);

/* ===== Usage window (full months, excludes current month) ===== */
DECLARE @WindowStart DATE = DATEFROMPARTS(YEAR(DATEADD(MONTH,-@UsageMonths,@Today)), MONTH(DATEADD(MONTH,-@UsageMonths,@Today)), 1);
DECLARE @WindowEnd   DATE = EOMONTH(DATEADD(MONTH,-1,@Today));
DECLARE @WindowDays  INT  = DATEDIFF(DAY,@WindowStart,@WindowEnd) + 1;
DECLARE @WorkDays    INT  = CAST(@WindowDays * (5.0/7.0) AS INT);   -- approx 5-day weeks

DECLARE @StartPeriod INT = YEAR(@WindowStart) * 100 + MONTH(@WindowStart);
DECLARE @EndPeriod   INT = YEAR(@WindowEnd)   * 100 + MONTH(@WindowEnd);

/* ===== Known locations (anything else = CONSIGNMENT) ===== */
CREATE TABLE #locs (
  location_id   INT          NOT NULL PRIMARY KEY,
  location_name VARCHAR(100) NOT NULL,
  is_corp       BIT          NOT NULL
);

INSERT INTO #locs (location_id, location_name, is_corp) VALUES
 (100,   'Corp Dallas',       1),
 (110,   'Corp Houston',      1),
 (300,   'Corp SFS',          1),
 (500,   'Corp Chicago',      1),
 (700,   'Corp Jacksonville', 1),
 (710,   'Corp Atlanta',      1),
 (10000, 'Dallas',            0),
 (11000, 'Houston',           0),
 (11500, 'San Antonio',       0),
 (12000, 'Baton Rouge',       0),
 (20000, 'Phoenix',           0),
 (21000, 'Las Vegas',         0),
 (30000, 'Santa Fe Springs',  0),
 (30100, 'San Diego',         0),
 (31000, 'San Leandro',       0),
 (31500, 'Sacramento',        0),
 (40000, 'Seattle',           0),
 (50000, 'Chicago',           0),
 (70000, 'Jacksonville',      0),
 (71000, 'Atlanta',           0);

/* ===== Corp purchasing team (name fragments matched against the PO requester) ===== */
CREATE TABLE #purch_buyers (name_fragment VARCHAR(50) NOT NULL PRIMARY KEY);
INSERT INTO #purch_buyers (name_fragment) VALUES
 ('ZEVELY'), ('GAMBRELL'), ('RITTER'), ('MCCARDELL'), ('LUND'), ('LEER');

/* ===== Map receipts to PO + requester (latest PO per receipt) ===== */
SELECT receipt_number, po_no, requested_by_name
INTO #po_map
FROM (
    SELECT
        irh.receipt_number,
        ph.po_no,
        c.first_name + ' ' + c.last_name AS requested_by_name,
        ROW_NUMBER() OVER (PARTITION BY irh.receipt_number ORDER BY ph.po_no DESC) AS rnk
    FROM dbo.inventory_receipts_hdr irh
    LEFT JOIN dbo.po_hdr   ph ON ph.po_no = irh.po_number
    LEFT JOIN dbo.contacts c  ON c.id    = ph.requested_by
) x
WHERE x.rnk = 1;

CREATE CLUSTERED INDEX ix_po_map ON #po_map (receipt_number);

/* ===== FIFO Base (one row per open layer, all locations) ===== */
SELECT
    inv_sup.supplier_id,
    sup.supplier_name,
    fl.document_no                               AS fifo_layer_no,
    CAST(fl.date_received AS DATE)               AS date_received,
    DATEDIFF(DAY, fl.date_received, @Today)      AS days_since_received_layer,
    fl.cost                                      AS fifo_layer_cost,
    inv_sup.cost                                 AS replacement_cost,
    fl.qty_received,
    fl.fifo_layer_qty                            AS qty_remaining,
    fl.fifo_layer_qty * fl.cost                  AS cost_on_hand,
    fl.location_id,
    ISNULL(L.location_name, 'Consignment')       AS location_name,
    CASE WHEN L.location_id IS NULL THEN 'CONSIGNMENT'
         WHEN L.is_corp = 1         THEN 'CORP'
         ELSE 'BRANCH' END                       AS loc_type,
    im.item_id,
    im.item_desc                                 AS description,
    pv.abc_class,
    CASE WHEN pv.last_sale_date     > '19900101' THEN CAST(pv.last_sale_date     AS DATE) END AS last_sale_date,
    CASE WHEN pv.last_purchase_date > '19900101' THEN CAST(pv.last_purchase_date AS DATE) END AS last_purchase_date,
    ISNULL(cl.class_description, '(no product group)') AS product_group,
    pv.stockable,
    pv.inv_max,
    fl.journal,
    pm.po_no,
    pm.requested_by_name,
    COALESCE(NULLIF(LTRIM(RTRIM(pm.requested_by_name)), ''),
             CASE WHEN fl.journal = 'IR' THEN '(PO without requester)'
                  ELSE '(Non-PO: ' + ISNULL(fl.journal, '?') + ')' END) AS buyer,
    CASE WHEN fl.journal = 'IR' THEN 'PO Origin' ELSE 'Trace Needed' END AS origin_source,
    CASE
        WHEN fl.journal = 'IR' AND EXISTS (
             SELECT 1 FROM #purch_buyers pb
             WHERE CHARINDEX(pb.name_fragment, UPPER(ISNULL(pm.requested_by_name, ''))) > 0)
             THEN 'Purchasing Department'
        WHEN fl.journal = 'IR' THEN 'Branch'
        ELSE 'Non-PO/Trace'
    END                                          AS requester_dept
INTO #fifo_base
FROM dbo.fifo_layers fl
LEFT JOIN #locs L
  ON L.location_id = fl.location_id
JOIN dbo.inv_mast im
  ON im.inv_mast_uid = fl.inv_mast_uid
JOIN dbo.p21_item_location_view pv
  ON pv.inv_mast_uid = im.inv_mast_uid
 AND pv.location_id  = fl.location_id
LEFT JOIN dbo.class cl          -- LEFT: items with no product group still count as inventory
  ON cl.class_id = im.class_id1
JOIN dbo.inventory_supplier inv_sup
  ON inv_sup.inv_mast_uid = im.inv_mast_uid
 AND inv_sup.supplier_id  = pv.primary_supplier_id
JOIN dbo.supplier sup
  ON sup.supplier_id = inv_sup.supplier_id
LEFT JOIN #po_map pm
  ON pm.receipt_number = fl.document_no
 AND fl.journal = 'IR'
WHERE fl.complete         = 'N'
  AND pv.primary_supplier = 'Y'
  AND fl.fifo_layer_qty  >= @MinQtyRemaining
  AND pv.company_id       = @CompanyId;

/* ===== Usage ===== */
SELECT
    u.item_id,
    u.location_id,
    SUM(ISNULL(u.actual_usage,0)) AS total_usage
INTO #usageN
FROM dbo.p21_inventory_usage_view u
WHERE u.year_for_period * 100 + u.period BETWEEN @StartPeriod AND @EndPeriod
GROUP BY u.item_id, u.location_id;

/* ===== Recency + Classification ===== */
;WITH latest AS (
    SELECT
        item_id,
        location_id,
        MAX(date_received)      AS most_recent_receipt_date,
        MAX(last_sale_date)     AS most_recent_sale_date,
        MAX(last_purchase_date) AS most_recent_purchase_date
    FROM #fifo_base
    GROUP BY item_id, location_id
)
SELECT
    fb.*,
    il.most_recent_receipt_date,
    DATEDIFF(DAY, il.most_recent_receipt_date,  @Today) AS _dsr,
    il.most_recent_sale_date,
    r.dss                                               AS _dss,
    il.most_recent_purchase_date,
    DATEDIFF(DAY, il.most_recent_purchase_date, @Today) AS _dsp,
    CASE WHEN fb.date_received < DATEADD(DAY,-@DeadDays,@Today) THEN 1 ELSE 0 END AS is_older_open_layer,
    s.inv_status,
    s.status_rank
INTO #classified
FROM #fifo_base fb
JOIN latest il
  ON il.item_id = fb.item_id AND il.location_id = fb.location_id
CROSS APPLY (SELECT dss = DATEDIFF(DAY, il.most_recent_sale_date, @Today)) r
CROSS APPLY (
    SELECT
        inv_status = CASE
            WHEN fb.loc_type = 'CONSIGNMENT'         THEN 'CONSIGNMENT'
            WHEN fb.loc_type = 'CORP'                THEN 'CORP'
            WHEN r.dss IS NULL OR r.dss >= @DeadDays THEN 'DEAD'
            WHEN r.dss >= @SlowDays                  THEN 'SLOW'
            WHEN r.dss >= @AgingDays                 THEN 'AGING'
            ELSE 'ACTIVE' END,
        status_rank = CASE
            WHEN fb.loc_type = 'CONSIGNMENT'         THEN -1
            WHEN fb.loc_type = 'CORP'                THEN 0
            WHEN r.dss IS NULL OR r.dss >= @DeadDays THEN 4
            WHEN r.dss >= @SlowDays                  THEN 3
            WHEN r.dss >= @AgingDays                 THEN 2
            ELSE 1 END
) s;

/* ===== Ranking (layer level) ===== */
SELECT *,
       ROW_NUMBER() OVER (PARTITION BY product_group ORDER BY cost_on_hand DESC) AS rn_pg_topN,
       ROW_NUMBER() OVER (ORDER BY cost_on_hand DESC)                            AS rn_overall
INTO #ranked
FROM #classified;

/* ===== Item rollup ===== */
SELECT
    c.location_id,
    c.location_name,
    c.loc_type,
    c.item_id,
    c.description,
    c.product_group,
    c.abc_class,
    c.supplier_id,
    c.supplier_name,
    c.stockable,
    SUM(c.qty_remaining)              AS qty_remaining,
    SUM(c.cost_on_hand)               AS cost_on_hand,
    MAX(c.replacement_cost)           AS replacement_cost,
    MAX(c.inv_max)                    AS inv_max,
    MAX(c.most_recent_receipt_date)   AS most_recent_receipt_date,
    MAX(c.most_recent_sale_date)      AS most_recent_sale_date,
    MAX(c.most_recent_purchase_date)  AS most_recent_purchase_date,
    MIN(c._dsr)                       AS days_since_recent_receipt,
    MIN(c._dss)                       AS days_since_recent_sale,
    MIN(c._dsp)                       AS days_since_recent_purchase,
    MIN(c.date_received)              AS oldest_open_layer_date,
    MAX(c.days_since_received_layer)  AS max_days_since_received_layer,
    SUM(c.is_older_open_layer)                                               AS older_layer_count,
    SUM(CASE WHEN c.is_older_open_layer = 1 THEN c.qty_remaining ELSE 0 END) AS qty_in_older_layers,
    SUM(CASE WHEN c.is_older_open_layer = 1 THEN c.cost_on_hand  ELSE 0 END) AS cost_in_older_layers,
    MAX(c.status_rank)                AS status_rank,
    CASE MAX(c.status_rank)
        WHEN -1 THEN 'CONSIGNMENT' WHEN 0 THEN 'CORP'
        WHEN 4  THEN 'DEAD'        WHEN 3 THEN 'SLOW'
        WHEN 2  THEN 'AGING'       ELSE 'ACTIVE' END AS inv_status
INTO #item_rollup
FROM #classified c
GROUP BY c.location_id, c.location_name, c.loc_type, c.item_id, c.description,
         c.product_group, c.abc_class, c.supplier_id, c.supplier_name, c.stockable;

/* ===== Most recent PO buyer per item/location (open IR layers) ===== */
SELECT item_id, location_id, buyer AS last_buyer, requester_dept AS last_buyer_dept, po_no AS last_po_no
INTO #last_buyer
FROM (
    SELECT c.item_id, c.location_id, c.buyer, c.requester_dept, c.po_no,
           ROW_NUMBER() OVER (PARTITION BY c.item_id, c.location_id
                              ORDER BY c.date_received DESC, c.fifo_layer_no DESC) AS rn
    FROM #classified c
    WHERE c.journal = 'IR'
) x
WHERE x.rn = 1;

/* ===== Outputs ===== */

/* A) Item Rollup + usage, days on hand and most recent buyer (the dashboard's main data) */
SELECT ir.*,
       ISNULL(u.total_usage,0)                                                           AS total_usage,
       ISNULL(u.total_usage,0) * 1.0 / @UsageMonths                                      AS avg_monthly_usage,
       ROUND(ir.qty_remaining / NULLIF(ISNULL(u.total_usage,0) * 1.0 / @WorkDays, 0), 1) AS days_on_hand,
       lb.last_buyer,
       lb.last_buyer_dept,
       lb.last_po_no
FROM #item_rollup ir
LEFT JOIN #usageN u
  ON u.item_id = ir.item_id AND u.location_id = ir.location_id
LEFT JOIN #last_buyer lb
  ON lb.item_id = ir.item_id AND lb.location_id = ir.location_id
ORDER BY ir.location_id, ir.status_rank DESC, ir.cost_on_hand DESC;

/* B) Top-N by Product Group */
SELECT * FROM #ranked
WHERE rn_pg_topN <= @TopN_PerGroup
ORDER BY product_group, rn_pg_topN;

/* C) Top Offenders Overall */
SELECT * FROM #ranked
WHERE rn_overall <= @TopN_Overall
ORDER BY rn_overall;

/* D) Summary by Product Group */
SELECT product_group,
       COUNT(*)           AS layer_count,
       SUM(qty_remaining) AS total_qty_remaining,
       SUM(cost_on_hand)  AS total_cost_on_hand,
       SUM(CASE WHEN inv_status = 'DEAD'        THEN cost_on_hand ELSE 0 END) AS dead_cost,
       SUM(CASE WHEN inv_status = 'SLOW'        THEN cost_on_hand ELSE 0 END) AS slow_cost,
       SUM(CASE WHEN inv_status = 'AGING'       THEN cost_on_hand ELSE 0 END) AS aging_cost,
       SUM(CASE WHEN inv_status = 'ACTIVE'      THEN cost_on_hand ELSE 0 END) AS active_cost,
       SUM(CASE WHEN inv_status = 'CORP'        THEN cost_on_hand ELSE 0 END) AS corp_cost,
       SUM(CASE WHEN inv_status = 'CONSIGNMENT' THEN cost_on_hand ELSE 0 END) AS consignment_cost
FROM #classified
GROUP BY product_group;

/* E) Summary by Supplier */
SELECT supplier_id, supplier_name,
       SUM(qty_remaining) AS total_qty_remaining,
       SUM(cost_on_hand)  AS total_cost_on_hand,
       SUM(CASE WHEN inv_status = 'DEAD'        THEN cost_on_hand ELSE 0 END) AS dead_cost,
       SUM(CASE WHEN inv_status = 'SLOW'        THEN cost_on_hand ELSE 0 END) AS slow_cost,
       SUM(CASE WHEN inv_status = 'AGING'       THEN cost_on_hand ELSE 0 END) AS aging_cost,
       SUM(CASE WHEN inv_status = 'ACTIVE'      THEN cost_on_hand ELSE 0 END) AS active_cost,
       SUM(CASE WHEN inv_status = 'CORP'        THEN cost_on_hand ELSE 0 END) AS corp_cost,
       SUM(CASE WHEN inv_status = 'CONSIGNMENT' THEN cost_on_hand ELSE 0 END) AS consignment_cost
FROM #classified
GROUP BY supplier_id, supplier_name;

/* F) Summary by Location */
SELECT location_id, location_name, loc_type,
       COUNT(*)           AS layer_count,
       SUM(qty_remaining) AS total_qty_remaining,
       SUM(cost_on_hand)  AS total_cost_on_hand,
       SUM(CASE WHEN inv_status = 'DEAD'        THEN cost_on_hand ELSE 0 END) AS dead_cost,
       SUM(CASE WHEN inv_status = 'SLOW'        THEN cost_on_hand ELSE 0 END) AS slow_cost,
       SUM(CASE WHEN inv_status = 'AGING'       THEN cost_on_hand ELSE 0 END) AS aging_cost,
       SUM(CASE WHEN inv_status = 'ACTIVE'      THEN cost_on_hand ELSE 0 END) AS active_cost,
       SUM(CASE WHEN inv_status = 'CORP'        THEN cost_on_hand ELSE 0 END) AS corp_cost,
       SUM(CASE WHEN inv_status = 'CONSIGNMENT' THEN cost_on_hand ELSE 0 END) AS consignment_cost
FROM #classified
GROUP BY location_id, location_name, loc_type;

/* G) Status Mix */
SELECT inv_status,
       COUNT(*)          AS cnt,
       SUM(cost_on_hand) AS total_cost_on_hand
FROM #classified
GROUP BY inv_status;

/* H) Location + Status + Stockable */
SELECT location_id, location_name, loc_type, stockable, inv_status,
       COUNT(*)           AS layer_count,
       SUM(qty_remaining) AS total_qty_remaining,
       SUM(cost_on_hand)  AS total_cost_on_hand
FROM #classified
GROUP BY location_id, location_name, loc_type, stockable, inv_status;

/* I) DOH Item-level (workdays) */
SELECT
    ir.location_id,
    ir.loc_type,
    ir.inv_status,
    ir.supplier_name,
    ir.product_group,
    ir.item_id,
    ir.description,
    ir.qty_remaining AS total_qty_remaining,
    ROUND(ir.qty_remaining / NULLIF(ISNULL(u.total_usage,0) / @WorkDays, 0), 1) AS days_on_hand_numeric,
    ISNULL(CAST(ROUND(ir.qty_remaining / NULLIF(ISNULL(u.total_usage,0) / @WorkDays, 0), 1) AS NVARCHAR(50)), N'?') AS days_on_hand_display
FROM #item_rollup ir
LEFT JOIN #usageN u
  ON u.item_id = ir.item_id AND u.location_id = ir.location_id;

/* J) DOH Rollup (workdays) */
SELECT
    ir.location_id,
    ir.supplier_name,
    ir.product_group,
    SUM(ir.qty_remaining) AS total_qty,
    ROUND(SUM(ir.qty_remaining) / NULLIF(SUM(ISNULL(u.total_usage,0)) / @WorkDays, 0), 1) AS days_on_hand_rollup_numeric,
    ISNULL(CAST(ROUND(SUM(ir.qty_remaining) / NULLIF(SUM(ISNULL(u.total_usage,0)) / @WorkDays, 0), 1) AS NVARCHAR(50)), N'?') AS days_on_hand_rollup_display
FROM #item_rollup ir
LEFT JOIN #usageN u
  ON u.item_id = ir.item_id AND u.location_id = ir.location_id
GROUP BY ir.location_id, ir.supplier_name, ir.product_group;

/* K) Usage at every location for items holding DEAD/SLOW stock (transfer candidates) */
SELECT u.item_id, u.location_id, u.total_usage
FROM #usageN u
WHERE u.total_usage > 0
  AND u.item_id IN (SELECT item_id FROM #item_rollup WHERE inv_status IN ('DEAD','SLOW'));

/* L) Run info */
SELECT @Today AS run_date, @WindowStart AS usage_window_start, @WindowEnd AS usage_window_end,
       @WorkDays AS work_days, @UsageMonths AS usage_months, @CompanyId AS company_id,
       @DeadDays AS dead_days, @SlowDays AS slow_days, @AgingDays AS aging_days;

/* M) Open stock by buyer: every location, one row per location x item x requester.
      Join to output A on location_id + item_id for status, group, supplier. */
SELECT
    c.location_id,
    c.item_id,
    c.buyer,
    c.requester_dept,
    c.origin_source,
    COUNT(*)                 AS layer_count,
    COUNT(DISTINCT c.po_no)  AS po_count,
    MAX(c.po_no)             AS latest_po_no,
    SUM(c.qty_remaining)     AS qty_remaining,
    SUM(c.cost_on_hand)      AS cost_on_hand,
    MIN(c.date_received)     AS first_received,
    MAX(c.date_received)     AS last_received
FROM #classified c
GROUP BY c.location_id, c.item_id, c.buyer, c.requester_dept, c.origin_source;

SET NOCOUNT OFF;
