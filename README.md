# Malaysia Cost of Living & Inflation Dashboard

End-to-end analysis of Malaysian inflation and everyday prices using official DOSM open data. Work in progress.

**Data caveat:** DOSM states that inflation analysis should use CPI data. PriceCatcher is a supplement for item-level detail, not an inflation measure.

## Setup (in progress)

1. Copy `.env.example` to `.env` and fill in your PostgreSQL password.
2. Create the database once (requires PostgreSQL's command-line tools):

   ```bash
   createdb -h localhost -U postgres cost_of_living
   ```

3. Create the schemas:

   ```bash
   psql -h localhost -U postgres -d cost_of_living -f sql/01_create_schemas.sql
   ```
