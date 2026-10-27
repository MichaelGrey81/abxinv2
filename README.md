# Inventory Health dashboard

Runs the dead / slow inventory classifier against P21 and shows the result as an
interactive dashboard for purchasing.

## Start it

Double-click **Start Dashboard.bat**, or run:

```
python inventory_app.py
```

The dashboard opens at http://127.0.0.1:8050. Click **Refresh from database** to run
the query. It shows the last cached result until a refresh finishes.

Requirements: Python 3, `pyodbc`, `openpyxl` and ODBC Driver 17 for SQL Server
(all already on this PC). Charts load Chart.js from cdnjs, so the browser needs internet access.

## International Enviroguard (company 2)

Double-click **Start IEG Dashboard.bat** (http://127.0.0.1:8051). It runs the same app and queries with
`config_ieg.ini`: company 2, its own name, its own data folder (`data_ieg`) and its own location list.
Both dashboards can run at once. **Nightly Refresh IEG.bat** refreshes it on a schedule.
To add another company, copy `config_ieg.ini`, change `[app]`, `company_id`, the port and `[locations]`.

## Connection

Edit **config.ini** for the server, database and login.

```
python inventory_app.py --test-connection
```

This PC connects with the SQL login `mgambrell_read`, the same login SSMS uses.
Double-click **Save Password.bat** once to store its password, encrypted with Windows DPAPI
so only your Windows account on this PC can read it. It tests the connection right after.
Run it again whenever the password changes. The password can also come from the
`INVDB_PASSWORD` environment variable.

## Files

| Path | What it is |
|---|---|
| `sql/inventory_classifier.sql` | The query. Still runs as-is in SSMS. The app rewrites the `DECLARE @Param = value;` lines. |
| `web/dashboard.html` | The dashboard page. |
| `data/latest.json` | Cached result of the last refresh. |
| `data/latest.xlsx` | Every query output (A–M) as one workbook. |
| `data/history.csv` | One snapshot per refresh date, by location and status. Feeds the trend chart. |

If you kept a history CSV from the old upload dashboard, copy it to `data/history.csv`.
It uses the same columns.

## Command line

```
python inventory_app.py --refresh                      run the query once and exit
python inventory_app.py --export report.html           write a self-contained HTML report from the cache
python inventory_app.py --refresh --dead-days 300      override a threshold for one run
python inventory_app.py --demo                         load made-up data to try the dashboard
```

**Nightly Refresh.bat** runs the query and saves a dated HTML report in `reports/`.
Schedule it in Windows Task Scheduler to build trend history automatically.

## What the dashboard shows

- **Status tiles** for cost on hand by status, with change since the previous snapshot. Click a tile to hide or show that status.
- **Opportunity tiles** for dead + slow at branches, transferable stock, excess on active items, old FIFO layers, and stock with no usage.
- **Overview** with the trend (weekly since January 1, rebuilt from transactions, then the saved snapshots), cost by location, days since sale, days on hand, top suppliers and top product groups.
- **Items**: every item-location. Click a row to see the item across the whole network.
- **Transfers**: dead or slow branch stock that another branch is using, with a suggested quantity.
- **Excess**: active or aging items above a target months of supply, or any item-location above its P21 max.
- **Buyer scorecard**: per person, POs written, PO lines and value (180 days), PO lines on time, cancel rate, stockouts and stockout rate on the suppliers they're assigned to, customer line fill, the dead + slow share of the stock they bought, and min/max and cost edits (90 days). Only branches count: corp DCs and consignment locations are left out of the POs, stockouts, fill, stock bought and min/max edits behind the score (cost changes are per item). Leaderboards rank the top five on each; a 0–100 score and A–F grade (A 80+, B 65+, C 50+, D 35+) compare people within the corporate team (or everyone with 25+ POs or edits) on two things, half each: the stockout rate on their suppliers' items at the branches (8% earns 0, 1.5% or better full marks) and productivity, branch PO lines written in 180 days against the group median (the median or more earns full marks). Fill, dead + slow, on-time, cancels and edits are shown for context but don't affect the grade. Every person gets a plain explanation of their grade and a step-by-step plan to reach an A. **Share cards** (button on the scorecard, or in a person's panel) make a card for one buyer: their grade, measures vs the team median and target, the plan to an A, and a ranking where everyone else's numbers show but their names are blurred placeholders; other names are never written into the file. Download as .html, as a .png image, or every card in one .zip. Clicking a person shows their score breakdown, plain-language things to point out against the group median, and every cost and min/max change they made. Cost changes are checked against the item's median PO price over the last year: a 50%+ change that lands 25%+ away from what we have been paying is marked worth a look; costs set to $0 are counted separately.
- **Branch performance**: each branch scored on line fill 30, stockout rate 30, dead + slow share 20 and turns 20, ranked best to worst, next to how much of its purchasing the corporate team does vs branch staff (branch PO lines, 180 days, and stock on hand by who wrote the PO). A bubble chart sets performance against corporate share; click a branch for what stands out and who writes its POs.
- **Vendor scorecard table** can be limited to vendors over a purchase amount (last 12 months: $25K+ up to $5M+, or a custom figure).
- **Who bought the stock on hand** (under the scorecard): dead and slow stock still on hand by PO requester, split into Purchasing Department, Branch and Non-PO/Trace, plus department by stockable.
- **Bought by / Buyer filters** apply to every screen. The Items table shows each item's last buyer, and the item panel lists every buyer with open stock.
- **Breakdown** by supplier, product group, location or ABC class, for return-to-vendor and review conversations.
- **Largest layers**: the biggest open FIFO layers.

Every table exports to CSV.

## Add-on queries (sql/modules)

Each file in `sql/modules` runs after the main query, in parallel, and returns one result set.
They're read-only and each is based on one of your saved SSMS queries. If one fails, the rest of
the refresh still works and its screen shows the error. Drop a new `.sql` file in the folder to add one.

| Module | Based on | Feeds |
|---|---|---|
| `open_po` | Open PO Tracker, PO History with Dates | On order screen, on-order columns |
| `sales_12m` | sales_history_for_DB, SalesHistory Analysis | Turns, GMROI, GP %, days of inventory |
| `last_customer` | Dead Stock Last Customer | Who to sell slow and dead stock back to |
| `backorders` | Critical Item Not on PO, CNOPO | Service screen, backorders fixable by transfer |
| `stockouts` | StockoutTracker, Stockout Study | Service screen, days out of stock |
| `supplier_perf` | LeadTime Analysis, Fill Rate, Digest1 | Supplier scorecard |
| `return_window` | Digest1, Return Script v5 | Returns screen |
| `usage_trend` | 3 Year Usage, Usage Updated | 24-month demand chart and trend |
| `inventory_flow` | new | Inventory change: receipts, shipments, returns, adjustments and transfers per item-location, last 61 days vs the 61 before |
| `receipt_detail` | PO by FIFO, Purch History | Inventory change by buyer, and price vs volume in receipts |
| `inventory_history` | replaces Inventroy Valuation History | 52-week inventory value, rebuilt backward from today's FIFO value |
| `minmax_changes` | Audit Min Max Change (+ Pivot) | Min/max changes screen and buyer scorecard, last 90 days, with the editor's name |
| `cost_changes` | CostChangeAudit, Standard_Cost_Changed_By_Purchasing | Cost changes screen and buyer scorecard, last 90 days, with the editor's name and the item's 12-month median PO price |
| `buyer_activity` | PO by Buyer, Last PO Date by Buyer, PO Changed by Someone Other than Buyer | Buyer scorecard: branch POs, lines, value, on time, cancels, price edits, expedites per PO buyer, 180 days |
| `branch_purchasing` | (new) | Branch performance: branch PO lines, value and on-time by branch and writer, 180 days, plus whether each line's item was stocked at the branch when the PO was entered (rebuilt from the inv_loc audit trail: stockable, max, purchase class) and, if not, why it was bought: tied to a customer order or direct ship, sold at the branch within 30 days of the PO, or no customer demand seen |
| `branch_nonstock_items` | (new, same audit-trail rebuild) | Branch performance drawer: items each branch bought when they weren't stocked there, with POs, why bought, branch order lines and customers in 180 days, and whether stocked now; flags items bought on 3+ POs that sold 6+ lines as worth considering for stock |
| `status_history` | (new, same approach as inventory_history) | Overview trend before the first saved snapshot: cost on hand by location and status each week since January 1, from today's FIFO value walked back through transactions, with status from the last sale before each date |
| `stockout_events` | StockoutTracker, Stockout Study | Stockout analysis: root cause, lost sales, repeat offenders |
| `fill_rate` | (new) | Fill rate: customer order lines for stocked items shipped complete within 2 business days, by item-location; also the order-line count behind the stockout rate |
| `fill_weekly` | (new) | Fill rate by week and location (trend chart) |
| `supplier_fill` | Fill Rate | Supplier delivery: on time in full, complete on first receipt, POs received in one receipt |
| `vendor_growth` | (new) | Vendor scorecard: monthly purchases (PO receipts) and sales/COGS per supplier, 24 months |
| `reorder_now` | Critical Item Not on PO, BelowOP | Vendor reorder focus: item-locations at or below min with nothing on order |

Windows are set by `DECLARE` lines at the top of each module (`@ChangeDays = 61`, `@AuditDays = 90`,
`@StockoutDays = 180`). Change them there.

Days on hand = cost on hand ÷ last-12-month COGS × 365 (calendar days). It appears per item-location
(Items), per item across the network, and rolled up by location, supplier, product group and ABC class
(Turns & GMROI). The older workday usage version is still available as a hidden column.

## Changes to the original query

The classification logic is unchanged. Additions:

- The item rollup also carries the primary supplier's replacement cost.
- Output A now includes total usage, average monthly usage and days on hand.
- Output K returns other-location usage for items with dead or slow stock, which powers the transfers view.
- Output L returns the run date, usage window and thresholds.
- Every open FIFO layer is traced receipt to PO to the PO's requester. The corp purchasing team is `corp_buyers` under `[purchasing]` in the config file (last names, comma separated). It replaces the `#purch_buyers` list in the SQL at run time. Edit it when the team changes and run a refresh.
- Output A carries the P21 max and the most recent buyer. Output M gives open stock by location, item and buyer, across every location.

## Using the charts and filters

- Click a chart bar to filter the table on that page (a chip appears). Click the same bar again to undo.
  On Overview a click filters the whole dashboard; clicking again clears it.
- Double-click a chart for a detail drawer. Charts inside the drawer filter the drawer's table the same way.
  Drawers listing item-locations have a "By item" switch that rolls everything up to one line per item.
- Status tiles: click to show only that status, Ctrl-click to add or remove more, click again to show all,
  double-click for an item-level list of that status.
- Location, Product group, Supplier, ABC, Bought by and Buyer are multi-select: tick as many as you need.
- Executive summary (header) and Buyer reviews (Stockout analysis, Vendor reorder focus) export plain text or PDF.
- Stockouts and the reorder list always go to the buyer assigned to the item's primary supplier in P21, even when someone else wrote the PO. Suppliers set to "Buyer Branch Specific" keep that name; there is no fallback to PO requesters.
- Buyer reviews cover the corporate purchasing team plus one review for "Buyer Branch Specific". Team averages are over the corporate team only.
- Stockout rate (Stockout analysis) = stockout events ÷ customer order lines for stocked items at the branches over the same 180 days.
- Fill rate: a line is filled when its full quantity ships within 2 business days of entry (weekends skipped, holidays not). P21 doesn't keep the quantity allocated at order entry, so pick-ticket ship dates are used. Change `@FillWindowDays` in `fill_rate.sql` and `fill_weekly.sql` to use a different window.
- Vendor scorecard (Vendors section): each vendor with $10K+ purchased or on hand gets a 0–100 score (on time in full 20, customer line fill 20, stockout rate 15, dead + slow share 15, turns 15, gross margin 10, return policy 5) and a grade. Click a vendor for growth, profit, delivery, service, returns, a 24-month chart and the score breakdown. Rebates, co-op, payment and freight terms and notes typed there are saved to `vendor_terms.json` in the data folder (live dashboard only) and appear in saved reports.
- Stockout analysis: clicking a bar in "Stockouts by ABC class", or a row when the table is grouped by ABC class, opens a drawer of the stocked-out items in that class (one row per item-location, with a toggle to see each stockout).
- Buyer dashboards (Buyer reviews dialog): "Buyer dashboard (.html)" or "All buyer dashboards (.zip)" saves one self-contained, interactive file per buyer with stockouts by vendor, ABC class, cause and location, repeat offenders and every stockout. No internet is needed to open it. Buyers click bars or vendor rows to filter, type notes on vendors and items, and press "Email feedback" to send them to `feedback_email` in the config file. Notes stay in their browser until sent. "All buyers, separate PDFs (.zip)" gives one PDF per team buyer.

## Sample mode (hidden)

Press **Ctrl+Alt+D**, or click the logo five times quickly, to switch the dashboard to a made-up dataset
and back. It's a fictional industrial distributor (two DCs, 14 branches, about 4,000 SKUs, $15M of
inventory) with invented cities, suppliers, items, customers, buyers and PO numbers; `demo_data.py`
checks every name and id against the live caches and reports any overlap. Every screen works, the
sidebar reads like a live connection, and Refresh runs a pretend refresh that never touches the
database. The data lives in `data_demo/` (git-ignored) and is rebuilt automatically each day so its
dates stay current; run `python demo_data.py` to rebuild it by hand. The choice is remembered per
browser; exports made in sample mode contain only sample data.

## Notes on the data

- Items with no product group are kept (shown as "(no product group)"). Earlier they were dropped by the
  classifier's join, which hid $683K at Abatix and most of Enviroguard's stock.
- Every add-on query is limited to the dashboard's company, including inventory transactions, sales history
  and audit trail changes.
- Stockouts only count stockable items with a max above zero.
#   a b x i n v 2  
 