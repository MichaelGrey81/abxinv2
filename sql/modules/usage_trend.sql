/* ============================================
   MONTHLY USAGE TREND, NETWORK TOTAL  (module: usage_trend)
   Based on: 3 Year Usage, Usage Updated, Usage Pivoted Down
   For every item with open FIFO stock: actual usage per month for the last
   @TrendMonths full months, summed across all locations, packed as
   "yyyymm:qty" pairs. The dashboard draws it in the item panel and flags
   items whose demand is rising or falling.
   ============================================ */
SET NOCOUNT ON;
DECLARE @CompanyId   INT = 1;
DECLARE @TrendMonths INT = 24;
DECLARE @Today DATE = CAST(GETDATE() AS DATE);
DECLARE @StartYm INT = YEAR(DATEADD(MONTH, -@TrendMonths, @Today)) * 100 + MONTH(DATEADD(MONTH, -@TrendMonths, @Today));
DECLARE @EndYm   INT = YEAR(DATEADD(MONTH, -1, @Today)) * 100 + MONTH(DATEADD(MONTH, -1, @Today));

DROP TABLE IF EXISTS #items;
SELECT DISTINCT fl.inv_mast_uid INTO #items
FROM dbo.fifo_layers fl
WHERE fl.complete = 'N' AND fl.fifo_layer_qty > 0 AND fl.company_id = @CompanyId;
CREATE CLUSTERED INDEX ix_items ON #items (inv_mast_uid);

;WITH m AS (
    SELECT u.item_id, u.year_for_period * 100 + u.period AS ym, SUM(ISNULL(u.actual_usage, 0)) AS qty
    FROM dbo.p21_inventory_usage_view u
    JOIN #items i ON i.inv_mast_uid = u.inv_mast_uid
    WHERE u.year_for_period * 100 + u.period BETWEEN @StartYm AND @EndYm
      AND u.company_id = @CompanyId
    GROUP BY u.item_id, u.year_for_period * 100 + u.period
)
SELECT
    item_id,
    STRING_AGG(CONCAT(ym, ':', CAST(ROUND(qty, 2) AS DECIMAL(19,2))), ',') WITHIN GROUP (ORDER BY ym) AS months
FROM m
GROUP BY item_id;
