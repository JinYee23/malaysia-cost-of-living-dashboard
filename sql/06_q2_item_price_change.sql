-- Q2: Which everyday items rose (or fell) most in price?
--
-- Method: matched premises
--   Compare the first and last month in the data (today: July vs September 2026).
--   Only premises that reported an item in BOTH months are used, so a change in which
--   shops reported cannot create a fake price movement.
--
--   1. Each premise's monthly price for an item = its median daily price that month.
--   2. Each matched premise gets a % change and an RM change between the two months.
--   3. An item's change = the median of its premises' changes, so every premise gets an
--      equal say and a few extreme premises cannot dominate.
--   4. Items need at least 30 matched premises, so rankings rest on enough evidence.
--
-- Caution: two months apart is short; large changes may be seasonal rather than lasting.
--
-- Run with: psql -f sql/06_q2_item_price_change.sql

-- One row per item with its matched-premise price change. A TEMP view only exists for
-- this session, so nothing is saved in the database.
CREATE TEMP VIEW item_change AS
WITH months AS (
    -- First and last month in the price data, found from the data rather than typed in
    SELECT min(d.month_start) AS first_month, max(d.month_start) AS last_month
    FROM mart.fact_prices AS f
    JOIN mart.dim_date AS d ON d.date = f.date
),
premise_month AS (
    -- Step 1: each premise's median price for each item, in the first and last month
    SELECT
        f.item_code,
        f.premise_code,
        d.month_start,
        percentile_cont(0.5) WITHIN GROUP (ORDER BY f.price) AS median_price
    FROM mart.fact_prices AS f
    JOIN mart.dim_date AS d ON d.date = f.date
    CROSS JOIN months AS m
    WHERE d.month_start IN (m.first_month, m.last_month)
    GROUP BY f.item_code, f.premise_code, d.month_start
),
matched AS (
    -- Step 2: keep only premises with a price in both months (the inner join drops the rest)
    SELECT
        s.item_code,
        s.premise_code,
        s.median_price AS start_price,
        e.median_price AS end_price
    FROM premise_month AS s
    JOIN premise_month AS e
      ON e.item_code = s.item_code
     AND e.premise_code = s.premise_code
    CROSS JOIN months AS m
    WHERE s.month_start = m.first_month
      AND e.month_start = m.last_month
)
-- Step 3: summarise each item across its matched premises
SELECT
    i.item_code,
    i.item,
    i.unit,
    count(*) AS matched_premises,
    round(percentile_cont(0.5) WITHIN GROUP (ORDER BY mt.start_price)::numeric, 2) AS median_start_price,
    round(percentile_cont(0.5) WITHIN GROUP (ORDER BY mt.end_price)::numeric, 2) AS median_end_price,
    round(percentile_cont(0.5) WITHIN GROUP (ORDER BY mt.end_price - mt.start_price)::numeric, 2) AS median_change_rm,
    round(percentile_cont(0.5) WITHIN GROUP (ORDER BY (mt.end_price / mt.start_price - 1) * 100)::numeric, 1) AS median_change_pct
FROM matched AS mt
JOIN mart.dim_item AS i ON i.item_code = mt.item_code
GROUP BY i.item_code, i.item, i.unit
HAVING count(*) >= 30;   -- Step 4: enough matched premises


-- 1. Top 10 items with the largest price rises.
--    Ranking happens before filtering, so items tied at 10th place are all shown.
SELECT *
FROM (
    SELECT
        RANK() OVER (ORDER BY median_change_pct DESC) AS rank,
        item, unit, matched_premises,
        median_start_price, median_end_price, median_change_rm, median_change_pct
    FROM item_change
) AS ranked
WHERE rank <= 10
ORDER BY rank, item;


-- 2. Top 10 items with the largest price falls.
SELECT *
FROM (
    SELECT
        RANK() OVER (ORDER BY median_change_pct ASC) AS rank,
        item, unit, matched_premises,
        median_start_price, median_end_price, median_change_rm, median_change_pct
    FROM item_change
) AS ranked
WHERE rank <= 10
ORDER BY rank, item;
