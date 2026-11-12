# Power BI dashboard spec

A build guide for the Malaysia Cost of Living & Inflation dashboard in Power BI Desktop.
It connects to the PostgreSQL database built by this project and has four pages:
**Overview**, **Category drill-down**, **Item price tracker** and **Basket comparison**.

**How the analysis reaches Power BI (hybrid approach)**

| Question | Calculated in | Why |
|---|---|---|
| Q1 State inflation and categories | **DAX** on `fact_cpi` | Year-on-year is standard DAX time intelligence, and viewers can pick any state, category or month |
| Q2 Item price changes | **SQL**, saved as `report.q2_item_change` | Matched premises (same shop in both months) is complex to rebuild in DAX |
| Q3 Premise type prices | **SQL**, saved as `report.q3_type_vs_cell` | Comparing each premise type with its own item-and-state median is complex in DAX. Saved per item and state, so it can still be filtered |
| Q4 Basket cost | **DAX** on `fact_prices`, using `report.basket_item` | A median of premise prices per state is natural in DAX, and viewers can pick any month |

Before building, run the pipeline so the database is up to date (see the README).

---

## 1. Connect Power BI to PostgreSQL

1. Open Power BI Desktop. Select **Home → Get data → More… → Database → PostgreSQL database → Connect**.
2. Enter:
   - **Server:** `localhost:5432`
   - **Database:** `cost_of_living`
   - **Data connectivity mode:** **Import**
3. When asked for credentials, choose the **Database** tab and enter user `postgres` and your password (the one in your `.env`). If Power BI warns that the connection is not encrypted, accept it. That is expected for a database on your own computer.
4. In the Navigator, tick these 10 tables, then select **Transform Data**:
   - `mart.dim_date`, `mart.dim_state`, `mart.dim_division`, `mart.dim_item`, `mart.dim_premise`
   - `mart.fact_cpi`, `mart.fact_prices`
   - `report.q2_item_change`, `report.q3_type_vs_cell`, `report.basket_item`
5. In Power Query, rename each query to drop the schema prefix (e.g. `mart dim_item` → `dim_item`, `report q2_item_change` → `q2_item_change`). The DAX below uses these short names.
6. Select **Close & Apply**. Loading 22 million price rows takes a few minutes.

**Why Import mode:** Power BI copies the data into its own compressed in-memory engine, so every click is fast. *DirectQuery* would send a SQL query to PostgreSQL on every click, which is slow over 22M rows. The trade-off is that Import shows the data as of the last **Refresh**: after re-running the pipeline, select **Home → Refresh**.

**CSV fallback:** without PostgreSQL, use **Get data → Text/CSV** on the files in `outputs/csv/` instead. `fact_prices.csv` is not in the repository because it is too large (565 MB); create it with `python src/export_csv.py`.

**Never share your `.pbix` with saved credentials.** Power BI stores the password in your local settings, not in the file, but check **File → Options and settings → Data source settings** before sharing.

---

## 2. Data model

Open **Model view** and check these relationships. Power BI usually detects most of them from the matching column names; create any that are missing by dragging one column onto the other.

| From (many side) | To (one side) | Notes |
|---|---|---|
| `fact_prices[date]` | `dim_date[date]` | |
| `fact_prices[item_code]` | `dim_item[item_code]` | |
| `fact_prices[premise_code]` | `dim_premise[premise_code]` | |
| `dim_premise[state]` | `dim_state[state]` | The snowflake branch: prices reach state through the premise |
| `fact_cpi[date]` | `dim_date[date]` | CPI months are stored as the 1st of the month |
| `fact_cpi[state]` | `dim_state[state]` | |
| `fact_cpi[division]` | `dim_division[division]` | |
| `q2_item_change[item_code]` | `dim_item[item_code]` | |
| `q3_type_vs_cell[item_code]` | `dim_item[item_code]` | |
| `q3_type_vs_cell[state]` | `dim_state[state]` | |

- Keep every relationship **single direction** (from the dimension to the fact), which is Power BI's default.
- Leave **`basket_item` unconnected** (a "disconnected table"). The basket measures use it as a list of item codes, so it must not filter anything by itself.
- Select `dim_date`, then **Table tools → Mark as date table**, using the `date` column. DAX time functions such as `SAMEPERIODLASTYEAR` need this.
- Hide key columns that viewers don't need (codes, `month_start`) to keep the field list tidy.

---

## 3. DAX measures

Create a blank table called `_Measures` (**Home → Enter data → Load**) and add each measure to it with **New measure**. A **measure** is a formula that recalculates for whatever the viewer has filtered, unlike a calculated column, which is fixed when data loads.

### Q1: inflation (from `fact_cpi`)

```dax
CPI Index = AVERAGE ( fact_cpi[cpi_index] )
```
The CPI index for whatever is filtered (one state, one category, one month gives exactly one value).

```dax
CPI Index Last Year = CALCULATE ( [CPI Index], SAMEPERIODLASTYEAR ( dim_date[date] ) )
```
`SAMEPERIODLASTYEAR` shifts the date filter back exactly one year. This is the DAX equivalent of `LAG(cpi_index, 12)` in `sql/05_q1_state_inflation.sql`.

```dax
Inflation YoY % = DIVIDE ( [CPI Index] - [CPI Index Last Year], [CPI Index Last Year] )
```
Year-on-year inflation. `DIVIDE` returns blank instead of an error when last year is missing. Format as **Percentage, 1 decimal**.

```dax
Latest CPI Month = CALCULATE ( MAX ( fact_cpi[date] ), REMOVEFILTERS ( dim_date ) )
```
The newest month in the CPI data, ignoring any date slicer, so "latest" updates itself when data is refreshed.

```dax
Inflation YoY % (Latest) =
VAR LatestMonth = [Latest CPI Month]
RETURN
    CALCULATE ( [Inflation YoY %], dim_date[date] = LatestMonth )
```
Inflation in the latest month only. `VAR` stores the latest month first, so it is worked out once.

```dax
Overall Inflation (Latest) =
CALCULATE ( [Inflation YoY % (Latest)], dim_division[division] = "overall" )
```
All-items inflation, used when no category is chosen.

*Caution:* with several states selected, `CPI Index` averages their indices without population weights, so it is not an official national figure. Show these measures per state.

### Q2: item prices (from `fact_prices` and `q2_item_change`)

```dax
Median Price = MEDIAN ( fact_prices[price] )
```
The middle price for the current filter, robust to odd prices. Format as **RM, 2 decimals**.

```dax
Premises Reporting = DISTINCTCOUNT ( fact_prices[premise_code] )
```
How many shops a price is based on, the evidence behind each number.

```dax
Top Riser =
VAR TopItem = TOPN ( 1, q2_item_change, q2_item_change[median_change_pct], DESC )
RETURN
    MAXX ( TopItem, q2_item_change[item] & "  " & FORMAT ( q2_item_change[median_change_pct] / 100, "+0%" ) )
```
The item with the largest matched-premise price rise, as text for a card (e.g. "TOMATO  +75%"). `median_change_pct` is stored in percent units, so it is divided by 100 before formatting.

### Q3: premise types (from `q3_type_vs_cell`)

```dax
Gap vs Local Median % = MEDIAN ( q3_type_vs_cell[pct_diff] ) / 100
```
The typical % a premise type charges above (+) or below (−) the local median for the same item. Each row of `q3_type_vs_cell` is one item in one state, so item and state slicers filter it directly. Format as **Percentage, 1 decimal**.

```dax
Wet Market vs Hypermarket Gap =
VAR WetMarket = CALCULATE ( [Gap vs Local Median %], q3_type_vs_cell[premise_type] = "Pasar Basah" )
VAR Hypermarket = CALCULATE ( [Gap vs Local Median %], q3_type_vs_cell[premise_type] = "Hypermarket" )
RETURN WetMarket - Hypermarket
```
The gap between the dearest and cheapest premise type, in percentage points.

### Q4: basket (from `fact_prices` and `basket_item`)

```dax
Item Price (State Median) =
MEDIANX ( VALUES ( fact_prices[premise_code] ), CALCULATE ( MEDIAN ( fact_prices[price] ) ) )
```
For each premise with prices in the current filter, take its median price; then take the median across premises. Each shop counts once, however often it reports. This matches `sql/08_q4_basket_cost.sql`. `CALCULATE` inside the loop turns "this premise" into a filter (*context transition*).

```dax
Basket Cost =
SUMX (
    VALUES ( basket_item[item_code] ),
    VAR ThisItem = basket_item[item_code]
    RETURN CALCULATE ( [Item Price (State Median)], dim_item[item_code] = ThisItem )
)
```
Adds up the state median price of each of the 10 basket items. Because `basket_item` is disconnected, each item code is applied as a filter on `dim_item` by hand.

```dax
Basket Items Covered =
COUNTROWS (
    FILTER (
        VALUES ( basket_item[item_code] ),
        VAR ThisItem = basket_item[item_code]
        RETURN CALCULATE ( [Premises Reporting], dim_item[item_code] = ThisItem ) >= 5
    )
)
```
How many basket items have at least 5 premises in the current filter. This is the same "thin state" rule as the SQL.

```dax
Basket Cost (Complete) =
IF ( [Basket Items Covered] = COUNTROWS ( basket_item ), [Basket Cost] )
```
Shows the basket cost only when every item is well covered, and blank otherwise, so a state is never compared on fewer items.

```dax
Basket Gap =
VAR Costs = ADDCOLUMNS ( VALUES ( dim_state[state] ), "@cost", [Basket Cost (Complete)] )
VAR Complete = FILTER ( Costs, NOT ISBLANK ( [@cost] ) )
RETURN MAXX ( Complete, [@cost] ) - MINX ( Complete, [@cost] )
```
The RM difference between the most and least expensive complete state.

**Known limitation:** these basket measures show basket *cost* for any period a viewer picks, using all premises. The basket *change* over time in the README uses matched premises, which is not rebuilt in DAX. For the change, use the SQL result and chart.

---

## 4. Pages

Use the same colours as the README charts: blue `#2a78d6` for single values; for values above or below zero, a diverging scale from blue (lower) through grey `#f0efec` (zero) to red `#e34948` (higher).

### Page 1: Overview

The whole story in five seconds: one headline per question.

| Visual | Fields / measure | Notes |
|---|---|---|
| Clustered bar chart: **inflation by state** | Axis `dim_state[state]`; value `Overall Inflation (Latest)` | Sort descending. Title: "Inflation by state, latest month vs a year earlier" |
| Card: **biggest price rise** | `Top Riser` | Subtitle: "Same shops, Sep 2025 vs Sep 2026" |
| Card: **wet market vs hypermarket** | `Wet Market vs Hypermarket Gap` | Subtitle: "Same item, same state" |
| Card: **basket gap** | `Basket Gap` | Subtitle: "Most vs least expensive state, 10 essentials" |

No slicers on this page, so the headlines always show the full picture.

### Page 2: Category drill-down (Q1)

| Visual | Fields / measure | Notes |
|---|---|---|
| Matrix: **state × category** | Rows `dim_state[state]`; columns `dim_division[division_name]`; value `Inflation YoY % (Latest)` | **Conditional formatting → Background colour → Gradient** with the diverging colours above, centred on 0. This is the interactive version of the README heatmap |
| Line chart: **inflation trend** | Axis `dim_date[date]` (month level); value `Inflation YoY %` | Shows whether a state's latest rate is lasting or a one-month blip |
| Slicers | `dim_state[state]`, `dim_division[division_name]` | Set the category slicer to "All items" by default |

Add a text box: "Fastest-rising categories, not contributions: CPI weights are not in the data."

### Page 3: Item price tracker (Q2 and Q3)

One item slicer drives the whole page: *what is happening to the price of this item, and where is it cheapest?*

| Visual | Fields / measure | Notes |
|---|---|---|
| Slicer: **item** | `dim_item[item]` (dropdown with search) | Single select |
| Line chart: **monthly price** | Axis `dim_date[month_start]`; values `Median Price`, tooltip `Premises Reporting` | Q2 over all 13 months |
| Table: **biggest movers** | `q2_item_change[item]`, `[unit]`, `[median_change_pct]`, `[median_change_rm]`, `[matched_premises]` | Sort by `median_change_pct`. Shows all items when the slicer is cleared |
| Bar chart: **premise types** | Axis `q3_type_vs_cell[premise_type]`; value `Gap vs Local Median %` | Q3 for the selected item. Conditional colour: red above 0, blue below |
| Slicer: **state** | `dim_state[state]` | Filters the line chart and premise type bars |

Note on the page: "Changes compare the same premises in both months (at least 30). Premise type gaps compare the same item within the same state."

### Page 4: Basket comparison (Q4)

| Visual | Fields / measure | Notes |
|---|---|---|
| Bar chart: **basket cost by state** | Axis `dim_state[state]`; value `Basket Cost (Complete)` | Sort descending. States without full coverage show no bar |
| Matrix: **item prices by state** | Rows `basket_item[label]`; columns `dim_state[state]`; value `Item Price (State Median)` | Shows which items make a state dear or cheap |
| Card: **basket gap** | `Basket Gap` | |
| Slicer: **month** | `dim_date[month_start]` | Defaults to all 13 months |

Note on the page: "Sabah and W.P. Labuan are excluded: too few premises price the basket's rice or chicken. Basket change over time is in the README (matched premises)."

---

## 5. Check your measures against the SQL

After building, compare these with the SQL results (13 months, September 2025 to September 2026). If a number differs, check the relationships and filters first.

| Check | Where in Power BI | Expected (from SQL) |
|---|---|---|
| Highest inflation, latest month | Overview bar chart | Negeri Sembilan and W.P. Labuan, 2.4% (Sep 2026) |
| Lowest inflation | Overview bar chart | Sarawak, 0.5% |
| Kedah, Insurance & Financial Services | Page 2 matrix | 12.2% |
| Biggest price rise | Overview card | Tomato, +75% |
| Hypermarket gap, all items | Page 3, no slicers | −1.9% |
| Wet market gap, all items | Page 3, no slicers | +3.0% |
| Most expensive basket, all 13 months | Page 4, no month filter | W.P. Putrajaya, RM 148.26 |
| Cheapest basket, all 13 months | Page 4, no month filter | Perak, RM 135.43 |
| States in the basket chart | Page 4 | 14 (Sabah and W.P. Labuan blank) |
