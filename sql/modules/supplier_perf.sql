/* ============================================
   SUPPLIER PERFORMANCE, LAST 12 MONTHS  (module: supplier_perf)
   Based on: LeadTime Analysis, Lead Time tracker - EIM Final, Fill Rate,
             Digest1 (abix_supplier_return_policies)
   One row per supplier: received PO lines, average and median lead time
   (PO created to received), on-time share against the line due date,
   quantity fill rate, and the supplier's return policy.
   ============================================ */
SET NOCOUNT ON;
DECLARE @CompanyId INT = 1;
DECLARE @Months    INT = 12;

;WITH lines AS (
    SELECT
        ph.supplier_id,
        DATEDIFF(DAY, ph.date_created, pl.received_date)                         AS lead_days,
        CASE WHEN pl.received_date <= DATEADD(DAY, 1, COALESCE(pl.date_due, ph.date_due)) THEN 1 ELSE 0 END AS on_time,
        CAST(pl.qty_ordered  AS DECIMAL(19,4)) AS qty_ordered,
        CAST(pl.qty_received AS DECIMAL(19,4)) AS qty_received,
        CAST(pl.qty_received * pl.unit_price / NULLIF(pl.pricing_unit_size, 0) AS DECIMAL(19,2)) AS value_received
    FROM dbo.po_line pl
    JOIN dbo.po_hdr  ph ON ph.po_no = pl.po_no
    WHERE ph.date_created >= DATEADD(MONTH, -@Months, GETDATE())
      AND ph.delete_flag = 'N' AND pl.delete_flag = 'N' AND pl.cancel_flag = 'N'
      AND pl.received_date IS NOT NULL
      AND pl.qty_received > 0
      AND ph.company_no = @CompanyId
      AND DATEDIFF(DAY, ph.date_created, pl.received_date) BETWEEN 0 AND 365
),
med AS (
    SELECT DISTINCT supplier_id,
           PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY lead_days) OVER (PARTITION BY supplier_id) AS median_lead_days
    FROM lines
),
rp AS (
    SELECT supplier_id, MAX(timeframe_in_days) AS return_days, MAX(restock_percent) AS restock_percent,
           MAX(CAST(return_policy AS NVARCHAR(400))) AS return_policy, MAX(buyer_name) AS corp_buyer
    FROM dbo.abix_supplier_return_policies
    GROUP BY supplier_id
)
SELECT
    l.supplier_id,
    s.supplier_name,
    LTRIM(RTRIM(ISNULL(c.first_name, '') + ' ' + ISNULL(c.last_name, ''))) AS supplier_buyer,
    COUNT(*)                                                  AS lines_received,
    CAST(AVG(CAST(l.lead_days AS FLOAT)) AS DECIMAL(9,1))     AS avg_lead_days,
    CAST(MAX(m.median_lead_days) AS DECIMAL(9,1))             AS median_lead_days,
    CAST(AVG(CAST(l.on_time AS FLOAT)) AS DECIMAL(9,4))       AS on_time_rate,
    CAST(SUM(l.qty_received) / NULLIF(SUM(l.qty_ordered), 0) AS DECIMAL(9,4)) AS fill_rate,
    SUM(l.value_received)                                     AS value_received,
    MAX(rp.return_days)                                       AS return_days,
    MAX(CASE WHEN rp.restock_percent > 1 THEN rp.restock_percent / 100.0 ELSE rp.restock_percent END) AS restock_rate,
    MAX(rp.return_policy)                                     AS return_policy
FROM lines l
JOIN med m ON m.supplier_id = l.supplier_id
LEFT JOIN dbo.supplier s ON s.supplier_id = l.supplier_id
LEFT JOIN dbo.contacts c ON c.id = s.buyer_id
LEFT JOIN rp ON rp.supplier_id = l.supplier_id
GROUP BY l.supplier_id, s.supplier_name, c.first_name, c.last_name;
