-- Q1: Which states have the highest and lowest recent inflation,
--     and which CPI categories are rising fastest in each state?
--
-- Definitions
--   Inflation      : year-on-year (YoY) % change in the CPI index, the way DOSM reports it.
--   Recent         : the latest month in the data (found with max(date), not typed in).
--   Fastest-rising : categories with the highest YoY inflation in a state. Without CPI
--                    spending weights this shows which categories rose most, not how much
--                    each contributed to the state's overall inflation.
--
-- Run with: psql -f sql/05_q1_state_inflation.sql

-- Year-on-year inflation for every state, category and month, written once and reused below.
-- A TEMP view only exists for this session, so nothing is saved in the database.
--
-- LAG(cpi_index, 12) reads the value 12 rows earlier within the same state and category.
-- That equals 12 months earlier because every series is complete: 16 states x 14 categories
-- x 201 months (Jan 2010 to Sep 2026) = 45,024 rows, the size of mart.fact_cpi.
CREATE TEMP VIEW cpi_yoy AS
SELECT
    f.date,
    f.state,
    f.division,
    d.division_name,
    f.cpi_index,
    LAG(f.cpi_index, 12) OVER w AS cpi_index_last_year,
    round(((f.cpi_index / LAG(f.cpi_index, 12) OVER w - 1) * 100)::numeric, 1) AS yoy_pct
FROM mart.fact_cpi AS f
JOIN mart.dim_division AS d ON d.division = f.division
WINDOW w AS (PARTITION BY f.state, f.division ORDER BY f.date);


-- 1. States ranked by overall YoY inflation in the latest month.
--    RANK() gives tied states the same rank.
SELECT
    RANK() OVER (ORDER BY yoy_pct DESC) AS rank,
    state,
    date,
    yoy_pct
FROM cpi_yoy
WHERE division = 'overall'
  AND date = (SELECT max(date) FROM cpi_yoy)
ORDER BY rank, state;


-- 2. The three fastest-rising categories in each state in the latest month.
--    PARTITION BY state restarts the ranking for every state.
WITH ranked AS (
    SELECT
        state,
        division_name,
        yoy_pct,
        RANK() OVER (PARTITION BY state ORDER BY yoy_pct DESC) AS category_rank
    FROM cpi_yoy
    WHERE division <> 'overall'
      AND date = (SELECT max(date) FROM cpi_yoy)
)
SELECT state, category_rank, division_name, yoy_pct
FROM ranked
WHERE category_rank <= 3
ORDER BY state, category_rank;


-- 3. Twelve-month trend of each state's overall YoY inflation, to show whether the
--    latest ranking is lasting or a one-month blip.
SELECT state, date, yoy_pct
FROM cpi_yoy
WHERE division = 'overall'
  AND date > (SELECT max(date) FROM cpi_yoy) - interval '12 months'
ORDER BY state, date;
