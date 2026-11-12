-- Q4: How much does a fixed basket of 10 essentials cost in each state,
--     and how has it changed?
--
-- Basket: one unit of each item below, as sold (e.g. a 10 kg bag of rice, a tray of 30 eggs).
--   Items were chosen as what Malaysian households most commonly buy, using the item code
--   with the widest coverage for each. The basket has no vegetables, and the 10 kg rice and
--   5 kg cooking oil make up a large share of its cost.
--
-- Rules
--   1. A premise's price for an item = its median price (over the period or a month).
--   2. A state's item price = the median across its premises, so each premise counts equally.
--   3. A state is excluded if ANY basket item has fewer than 5 premises there. Prices are
--      never filled in, so every included state is compared on exactly the same 10 items.
--   4. Basket cost = the sum of the state's 10 item prices.
--   5. Change compares the first and last month using only premises that priced the item in
--      both months (matched premises, as in Q2), again requiring 5 per item and state.
--
-- Run with: psql -f sql/08_q4_basket_cost.sql

-- The basket, saved as report.basket_item so Power BI's DAX uses the same 10 items.
-- Dropped and rebuilt in one transaction, so it is safe to re-run.
BEGIN;
DROP TABLE IF EXISTS report.basket_item;
CREATE TABLE report.basket_item AS
SELECT * FROM (VALUES
    (2066, 'Rice, Faiza Emas 10 kg'),
    (1110, 'Eggs, Grade B 30'),
    (1,    'Chicken, standard 1 kg'),
    (1589, 'Sugar, white 1 kg'),
    (917,  'Flour, Cap Sauh 1 kg'),
    (263,  'Cooking oil, Cap Buruh 5 kg'),
    (214,  'Soy sauce, Kipas Udang 345 ml'),
    (191,  'Sardines, Cap Ayam 425 g'),
    (1476, 'Fish, ikan kembung 1 kg'),
    (180,  'Tea, Boh 100 bags')
) AS b (item_code, label);
ALTER TABLE report.basket_item ADD PRIMARY KEY (item_code);
COMMIT;

-- Each state's price for each basket item over the whole period (rules 1 and 2).
CREATE TEMP VIEW item_state AS
WITH premise_price AS (
    SELECT
        f.item_code,
        f.premise_code,
        p.state,
        percentile_cont(0.5) WITHIN GROUP (ORDER BY f.price) AS price
    FROM mart.fact_prices AS f
    JOIN report.basket_item AS b ON b.item_code = f.item_code
    JOIN mart.dim_premise AS p ON p.premise_code = f.premise_code
    GROUP BY f.item_code, f.premise_code, p.state
)
SELECT
    item_code,
    state,
    count(*) AS premises,
    percentile_cont(0.5) WITHIN GROUP (ORDER BY price) AS median_price
FROM premise_price
GROUP BY item_code, state;

-- States with at least 5 premises for every basket item (rule 3).
CREATE TEMP VIEW qualifying_state AS
SELECT state
FROM item_state
WHERE premises >= 5
GROUP BY state
HAVING count(*) = (SELECT count(*) FROM report.basket_item);


-- 1. Excluded states and why: every basket item with fewer than 5 premises in that state.
--    CROSS JOIN lists every state-item pair, so items with no premises at all show as 0.
SELECT
    s.state,
    string_agg(b.label || ' (' || coalesce(i.premises, 0) || ' premises)', '; ' ORDER BY b.label) AS too_few_premises
FROM mart.dim_state AS s
CROSS JOIN report.basket_item AS b
LEFT JOIN item_state AS i ON i.state = s.state AND i.item_code = b.item_code
WHERE coalesce(i.premises, 0) < 5
GROUP BY s.state
ORDER BY s.state;


-- 2. Basket cost by state over the whole period, most expensive first (rule 4).
SELECT
    RANK() OVER (ORDER BY sum(median_price) DESC) AS rank_most_expensive,
    state,
    round(sum(median_price)::numeric, 2) AS basket_cost_rm
FROM item_state
WHERE state IN (SELECT state FROM qualifying_state)
GROUP BY state
ORDER BY rank_most_expensive;


-- 3. Basket change between the first and last month, largest rise first (rule 5).
WITH months AS (
    SELECT min(d.month_start) AS first_month, max(d.month_start) AS last_month
    FROM mart.fact_prices AS f
    JOIN mart.dim_date AS d ON d.date = f.date
),
premise_month AS (
    SELECT
        f.item_code,
        f.premise_code,
        p.state,
        d.month_start,
        percentile_cont(0.5) WITHIN GROUP (ORDER BY f.price) AS price
    FROM mart.fact_prices AS f
    JOIN report.basket_item AS b ON b.item_code = f.item_code
    JOIN mart.dim_premise AS p ON p.premise_code = f.premise_code
    JOIN mart.dim_date AS d ON d.date = f.date
    CROSS JOIN months AS m
    WHERE d.month_start IN (m.first_month, m.last_month)
    GROUP BY f.item_code, f.premise_code, p.state, d.month_start
),
matched_item_state AS (
    -- Premises with a price in both months, summarised per item and state
    SELECT
        s.item_code,
        s.state,
        count(*) AS matched_premises,
        percentile_cont(0.5) WITHIN GROUP (ORDER BY s.price) AS start_price,
        percentile_cont(0.5) WITHIN GROUP (ORDER BY e.price) AS end_price
    FROM premise_month AS s
    JOIN premise_month AS e
      ON e.item_code = s.item_code
     AND e.premise_code = s.premise_code
    CROSS JOIN months AS m
    WHERE s.month_start = m.first_month
      AND e.month_start = m.last_month
    GROUP BY s.item_code, s.state
    HAVING count(*) >= 5
),
state_basket AS (
    -- Only states where all 10 items have enough matched premises
    SELECT
        state,
        sum(start_price) AS start_cost,
        sum(end_price) AS end_cost
    FROM matched_item_state
    GROUP BY state
    HAVING count(*) = (SELECT count(*) FROM report.basket_item)
)
SELECT
    RANK() OVER (ORDER BY end_cost / start_cost DESC) AS rank_largest_rise,
    state,
    round(start_cost::numeric, 2) AS first_month_cost_rm,
    round(end_cost::numeric, 2) AS last_month_cost_rm,
    round((end_cost - start_cost)::numeric, 2) AS change_rm,
    round(((end_cost / start_cost - 1) * 100)::numeric, 1) AS change_pct
FROM state_basket
ORDER BY rank_largest_rise;


-- 4. Each basket item's price in each included state, for charts and Power BI.
SELECT
    i.state,
    b.label AS item,
    i.premises,
    round(i.median_price::numeric, 2) AS median_price_rm
FROM item_state AS i
JOIN report.basket_item AS b ON b.item_code = i.item_code
WHERE i.state IN (SELECT state FROM qualifying_state)
ORDER BY i.state, b.label;
