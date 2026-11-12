-- Build the clean layer from the raw layer, applying the Phase 3 cleaning rules
-- (see notebooks/01_explore.ipynb, "Cleaning rules").
--
-- Every table is dropped and rebuilt, so this is safe to re-run after reloading raw.
-- BEGIN ... COMMIT makes the whole rebuild one transaction: if any statement fails,
-- nothing changes and the previous clean tables stay in place.
--
-- Rule 1 (months Jul-Sep 2026) is already true: only those months are loaded into raw.
-- Rule 6 (keep unit as a label) needs no change.

BEGIN;

-- Prices: rule 3 (text date -> real date) and rule 4 (outliers).
-- A price is an outlier if it is more than 5x or less than 1/5 of its item's median price.
DROP TABLE IF EXISTS clean.prices;
CREATE TABLE clean.prices AS
WITH item_median AS (
    -- percentile_cont(0.5) is the median, calculated the same way as pandas
    SELECT
        item_code,
        percentile_cont(0.5) WITHIN GROUP (ORDER BY price) AS median_price
    FROM raw.prices
    GROUP BY item_code
)
SELECT
    p.date::date AS date,
    p.premise_code,
    p.item_code,
    p.price
FROM raw.prices AS p
JOIN item_median AS m ON m.item_code = p.item_code
WHERE p.price <= m.median_price * 5
  AND p.price >= m.median_price / 5;

-- Items: rule 2 (drop the -1 "Unknown" row) and rule 5 (trim text).
DROP TABLE IF EXISTS clean.lookup_item;
CREATE TABLE clean.lookup_item AS
SELECT
    item_code,
    trim(item)          AS item,
    trim(unit)          AS unit,
    trim(item_group)    AS item_group,
    trim(item_category) AS item_category
FROM raw.lookup_item
WHERE item_code <> -1;

-- Premises: rule 2 and rule 5. Trimming merges 'Pasar Basah ' into 'Pasar Basah'.
DROP TABLE IF EXISTS clean.lookup_premise;
CREATE TABLE clean.lookup_premise AS
SELECT
    premise_code,
    trim(premise)      AS premise,
    trim(address)      AS address,
    trim(premise_type) AS premise_type,
    trim(state)        AS state,
    trim(district)     AS district
FROM raw.lookup_premise
WHERE premise_code <> -1;

-- CPI: rule 5 (trim text).
DROP TABLE IF EXISTS clean.cpi;
CREATE TABLE clean.cpi AS
SELECT
    trim(state)    AS state,
    date,
    trim(division) AS division,
    index
FROM raw.cpi;

-- CPI category names: rule 7 (only the 13 two-digit divisions) and rule 5.
DROP TABLE IF EXISTS clean.cpi_division;
CREATE TABLE clean.cpi_division AS
SELECT
    division,
    trim(desc_en) AS division_name
FROM raw.mcoicop
WHERE digits = 2;

COMMIT;
