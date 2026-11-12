-- Raw layer: one table per source, with values exactly as they appear in the files.
-- No cleaning happens here; the Phase 3 cleaning rules are applied in the clean layer.
-- Safe to re-run: IF NOT EXISTS skips tables that already exist.

-- PriceCatcher daily prices, all months in one table.
-- date stays as text because that is how the files store it (cleaning rule 3 converts it).
CREATE TABLE IF NOT EXISTS raw.prices (
    date          text,
    premise_code  integer,
    item_code     integer,
    price         double precision,
    source_file   text            -- which monthly file the row came from
);

-- State CPI by category (monthly index).
CREATE TABLE IF NOT EXISTS raw.cpi (
    state     text,
    date      date,
    division  text,               -- '01' to '13' or 'overall'; text keeps the leading zero
    index     double precision
);

-- What each PriceCatcher item_code means.
CREATE TABLE IF NOT EXISTS raw.lookup_item (
    item_code      integer,
    item           text,
    unit           text,
    item_group     text,
    item_category  text
);

-- What each PriceCatcher premise_code means, including its type and state.
CREATE TABLE IF NOT EXISTS raw.lookup_premise (
    premise_code  integer,
    premise       text,
    address       text,
    premise_type  text,
    state         text,
    district      text
);

-- Names for CPI category codes. "group" is quoted because GROUP is an SQL keyword.
CREATE TABLE IF NOT EXISTS raw.mcoicop (
    digits    integer,
    division  text,
    "group"   text,
    class     text,
    subclass  text,
    desc_en   text,
    desc_bm   text
);
