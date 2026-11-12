-- Create the three pipeline layers in the cost_of_living database.
-- Safe to re-run: IF NOT EXISTS skips schemas that already exist.
--
-- raw   : source files loaded exactly as downloaded, never edited
-- clean : raw data with the Phase 3 cleaning rules applied
-- mart  : star schema (facts and dimensions) for analysis and Power BI

CREATE SCHEMA IF NOT EXISTS raw;
CREATE SCHEMA IF NOT EXISTS clean;
CREATE SCHEMA IF NOT EXISTS mart;
