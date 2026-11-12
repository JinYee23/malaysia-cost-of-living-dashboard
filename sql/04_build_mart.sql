-- Build the mart layer: a star schema for analysis and Power BI, built from the clean layer.
--
--   dim_item ----+                         +---- dim_division
--   dim_date ----+---- fact_prices         |
--                |          |          fact_cpi ---- dim_date
--           dim_premise ----+              |
--                +--------- dim_state -----+
--
-- Prices reach state through dim_premise, because state is a property of the premise.
-- Keys are the existing codes (item_code, premise_code, state, division, date).
--
-- Each table is created from a query first, then keys and indexes are added.
-- Adding them after loading is faster than checking every row while inserting.
-- The whole rebuild is one transaction, so it is safe to re-run.

BEGIN;

-- Facts depend on dimensions, so drop them first.
DROP TABLE IF EXISTS mart.fact_prices;
DROP TABLE IF EXISTS mart.fact_cpi;
DROP TABLE IF EXISTS mart.dim_premise;
DROP TABLE IF EXISTS mart.dim_item;
DROP TABLE IF EXISTS mart.dim_state;
DROP TABLE IF EXISTS mart.dim_division;
DROP TABLE IF EXISTS mart.dim_date;

-- ---------------------------------------------------------------- dimensions

-- States: shared by prices (through premises) and CPI, so one state filter applies to both.
CREATE TABLE mart.dim_state AS
SELECT state FROM clean.cpi
UNION
SELECT state FROM clean.lookup_premise WHERE state IS NOT NULL;
ALTER TABLE mart.dim_state ADD PRIMARY KEY (state);

-- CPI categories: the 13 divisions plus 'overall' (all items combined).
CREATE TABLE mart.dim_division AS
SELECT division, division_name FROM clean.cpi_division
UNION ALL
SELECT 'overall', 'All items';
ALTER TABLE mart.dim_division ADD PRIMARY KEY (division);

-- Items: what each item_code is, with its unit as a label.
CREATE TABLE mart.dim_item AS
SELECT item_code, item, unit, item_group, item_category
FROM clean.lookup_item;
ALTER TABLE mart.dim_item ADD PRIMARY KEY (item_code);

-- Premises: each premise's type and location, linked to its state.
CREATE TABLE mart.dim_premise AS
SELECT premise_code, premise, premise_type, district, state
FROM clean.lookup_premise;
ALTER TABLE mart.dim_premise ADD PRIMARY KEY (premise_code);
ALTER TABLE mart.dim_premise ADD FOREIGN KEY (state) REFERENCES mart.dim_state (state);

-- Dates: one row per day covering both CPI (monthly, from 2010) and prices (daily).
-- CPI months are stored as the first day of the month, so they join on date too.
-- The range comes from the data itself: from the first month in either table to the
-- last day of the latest month. Adding months to the pipeline needs no change here.
CREATE TABLE mart.dim_date AS
WITH bounds AS (
    SELECT
        least((SELECT min(date) FROM clean.cpi), (SELECT min(date) FROM clean.prices))    AS first_date,
        greatest((SELECT max(date) FROM clean.cpi), (SELECT max(date) FROM clean.prices)) AS last_date
)
SELECT
    d::date                         AS date,
    extract(year FROM d)::int       AS year,
    extract(month FROM d)::int      AS month,
    to_char(d, 'Mon')               AS month_name,
    date_trunc('month', d)::date    AS month_start
FROM bounds,
     generate_series(
         date_trunc('month', first_date),
         date_trunc('month', last_date) + interval '1 month - 1 day',
         interval '1 day'
     ) AS d;
ALTER TABLE mart.dim_date ADD PRIMARY KEY (date);

-- ---------------------------------------------------------------- facts

-- Prices: one item's price at one premise on one day.
-- numeric(10,2) stores prices as exact decimals, avoiding floating-point rounding.
--
-- Only prices for items described in the item lookup are kept. In Jul-Sep 2026,
-- 14 item codes first recorded on 6 July 2026 (83,768 rows, 1.5%) are not in DOSM's
-- lookup yet, so they cannot be named in any analysis. They stay in raw and clean,
-- and return here automatically once DOSM adds them to the lookup.
CREATE TABLE mart.fact_prices AS
SELECT p.date, p.premise_code, p.item_code, p.price::numeric(10, 2) AS price
FROM clean.prices AS p
WHERE EXISTS (
    SELECT 1 FROM clean.lookup_item AS i WHERE i.item_code = p.item_code
);
ALTER TABLE mart.fact_prices ADD FOREIGN KEY (date) REFERENCES mart.dim_date (date);
ALTER TABLE mart.fact_prices ADD FOREIGN KEY (premise_code) REFERENCES mart.dim_premise (premise_code);
ALTER TABLE mart.fact_prices ADD FOREIGN KEY (item_code) REFERENCES mart.dim_item (item_code);

-- Indexes on the columns most queries filter or join on.
CREATE INDEX ON mart.fact_prices (date);
CREATE INDEX ON mart.fact_prices (item_code);
CREATE INDEX ON mart.fact_prices (premise_code);

-- CPI: one state's index for one category in one month.
CREATE TABLE mart.fact_cpi AS
SELECT date, state, division, index AS cpi_index
FROM clean.cpi;
ALTER TABLE mart.fact_cpi ADD FOREIGN KEY (date) REFERENCES mart.dim_date (date);
ALTER TABLE mart.fact_cpi ADD FOREIGN KEY (state) REFERENCES mart.dim_state (state);
ALTER TABLE mart.fact_cpi ADD FOREIGN KEY (division) REFERENCES mart.dim_division (division);

COMMIT;
