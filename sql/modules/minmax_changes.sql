/* ============================================
   MIN / MAX / REPLENISHMENT METHOD CHANGES  (module: minmax_changes)
   Based on: Audit Min Max Change, Audit Min Max Change with Curr - Pivot
   One row per item-location changed in the last @AuditDays: the value
   before the first change and after the last change for min, max and
   replenishment method, how many edits, and who made the last one.
   The dashboard prices the max change at FIFO unit cost to show how much
   target stock each change added or removed.
   ============================================ */
SET NOCOUNT ON;
DECLARE @CompanyId INT = 1;
DECLARE @AuditDays INT = 90;

;WITH a AS (
    SELECT at.inv_mast_uid, at.key2_value AS location_id, at.column_changed, at.old_value, at.new_value,
           at.created_by, at.date_created,
           ROW_NUMBER() OVER (PARTITION BY at.inv_mast_uid, at.key2_value, at.column_changed ORDER BY at.date_created ASC,  at.audit_trail_uid ASC)  AS rn_first,
           ROW_NUMBER() OVER (PARTITION BY at.inv_mast_uid, at.key2_value, at.column_changed ORDER BY at.date_created DESC, at.audit_trail_uid DESC) AS rn_last,
           ROW_NUMBER() OVER (PARTITION BY at.inv_mast_uid, at.key2_value ORDER BY at.date_created DESC, at.audit_trail_uid DESC)                    AS rn_item
    FROM dbo.audit_trail at
    WHERE at.date_created >= DATEADD(DAY, -@AuditDays, GETDATE())
      AND at.table_changed = 'inv_loc'
      AND at.key2_value IN (SELECT CAST(CAST(location_id AS BIGINT) AS VARCHAR(20)) FROM dbo.location WHERE company_id = @CompanyId)
      AND at.column_changed IN ('inv_min', 'inv_max', 'replenishment_method')
)
SELECT
    im.item_id,
    a.location_id,
    MAX(CASE WHEN column_changed = 'inv_min' AND rn_first = 1 THEN TRY_CAST(old_value AS DECIMAL(19,4)) END) AS min_before,
    MAX(CASE WHEN column_changed = 'inv_min' AND rn_last  = 1 THEN TRY_CAST(new_value AS DECIMAL(19,4)) END) AS min_after,
    MAX(CASE WHEN column_changed = 'inv_max' AND rn_first = 1 THEN TRY_CAST(old_value AS DECIMAL(19,4)) END) AS max_before,
    MAX(CASE WHEN column_changed = 'inv_max' AND rn_last  = 1 THEN TRY_CAST(new_value AS DECIMAL(19,4)) END) AS max_after,
    MAX(CASE WHEN column_changed = 'replenishment_method' AND rn_first = 1 THEN old_value END)             AS method_before,
    MAX(CASE WHEN column_changed = 'replenishment_method' AND rn_last  = 1 THEN new_value END)             AS method_after,
    COUNT(*)                                                    AS edits,
    MAX(CASE WHEN rn_item = 1 THEN a.created_by END)              AS changed_by,
    CAST(MAX(a.date_created) AS DATE)                           AS last_changed,
    CAST(MIN(a.date_created) AS DATE)                           AS first_changed
FROM a
JOIN dbo.inv_mast im ON im.inv_mast_uid = a.inv_mast_uid
GROUP BY im.item_id, a.location_id;
