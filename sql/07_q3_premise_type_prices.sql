-- Q3: Do prices for the same item differ by premise type
--     (hypermarket, supermarket, mini market, sundry shop, wet market)?
--
-- Method: compare within the same item AND the same state
--   Premise types are spread differently across states (e.g. 28% of hypermarkets are in the
--   Klang Valley vs 7% of sundry shops), so a plain average by premise type would partly
--   measure location. Comparing inside each item-and-state "cell" removes that effect.
--
--   1. Each premise's price for an item = its median price over the whole period.
--   2. Cell benchmark = the median price of ALL premises selling that item in that state.
--   3. Each premise type's median in the cell is expressed as % above (+) or below (-)
--      the benchmark. A type counts in a cell only with at least 5 premises, and a cell
--      needs at least 2 qualifying types to be a comparison.
--   4. Each premise type is summarised by the median of its % differences across cells,
--      so every item-and-state cell gets an equal say.
--
-- Run with: psql -f sql/07_q3_premise_type_prices.sql

-- One row per cell and premise type, with its % difference from the cell benchmark.
-- A TEMP view only exists for this session, so nothing is saved in the database.
CREATE TEMP VIEW type_vs_cell AS
WITH premise_price AS (
    -- Step 1: one price per premise and item
    SELECT
        f.item_code,
        f.premise_code,
        p.premise_type,
        p.state,
        percentile_cont(0.5) WITHIN GROUP (ORDER BY f.price) AS price
    FROM mart.fact_prices AS f
    JOIN mart.dim_premise AS p ON p.premise_code = f.premise_code
    GROUP BY f.item_code, f.premise_code, p.premise_type, p.state
),
cell_benchmark AS (
    -- Step 2: median of all premises for each item in each state
    SELECT
        item_code,
        state,
        percentile_cont(0.5) WITHIN GROUP (ORDER BY price) AS cell_median
    FROM premise_price
    GROUP BY item_code, state
),
type_in_cell AS (
    -- Step 3a: each premise type's median in a cell, if it has at least 5 premises there
    SELECT
        item_code,
        state,
        premise_type,
        count(*) AS premises,
        percentile_cont(0.5) WITHIN GROUP (ORDER BY price) AS type_median
    FROM premise_price
    GROUP BY item_code, state, premise_type
    HAVING count(*) >= 5
),
comparable_cell AS (
    -- Step 3b: keep cells where at least 2 premise types qualify
    SELECT item_code, state
    FROM type_in_cell
    GROUP BY item_code, state
    HAVING count(*) >= 2
)
SELECT
    t.item_code,
    t.state,
    t.premise_type,
    t.premises,
    t.type_median,
    b.cell_median,
    (t.type_median / b.cell_median - 1) * 100 AS pct_diff
FROM type_in_cell AS t
JOIN comparable_cell AS c ON c.item_code = t.item_code AND c.state = t.state
JOIN cell_benchmark AS b ON b.item_code = t.item_code AND b.state = t.state;


-- 1. Premise types ranked from cheapest to most expensive, relative to the local median.
--    pct_cells_below = share of cells where the type was cheaper than the benchmark.
SELECT
    RANK() OVER (ORDER BY percentile_cont(0.5) WITHIN GROUP (ORDER BY pct_diff)) AS rank_cheapest,
    premise_type,
    round(percentile_cont(0.5) WITHIN GROUP (ORDER BY pct_diff)::numeric, 1) AS median_pct_vs_local,
    round(100.0 * count(*) FILTER (WHERE pct_diff < 0) / count(*), 0) AS pct_cells_below,
    count(*) AS cells,
    count(DISTINCT item_code) AS items,
    count(DISTINCT state) AS states
FROM type_vs_cell
GROUP BY premise_type
ORDER BY rank_cheapest;


-- 2. The same comparison within each item group (e.g. fresh food vs packaged goods),
--    to check whether a premise type's price gap is consistent across kinds of goods.
SELECT
    i.item_group,
    v.premise_type,
    round(percentile_cont(0.5) WITHIN GROUP (ORDER BY v.pct_diff)::numeric, 1) AS median_pct_vs_local,
    count(*) AS cells
FROM type_vs_cell AS v
JOIN mart.dim_item AS i ON i.item_code = v.item_code
GROUP BY i.item_group, v.premise_type
ORDER BY i.item_group, median_pct_vs_local;
