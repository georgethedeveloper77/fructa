# One-off data corrections

These are NOT migrations. They correct rows rather than change shape, they were
each written against one manager's fact sheet, and they are not idempotent in
the way a migration must be, so they must never be picked up by `db push`.

Run order, if rebuilding from scratch after the migrations:

1. `mansax_special_return_basis.sql`
2. `oak_special_return_basis.sql`
3. `cytonn_chyf_yield_basis.sql`
4. `etica_special_multi_asset_return_basis.sql`
5. `specials_factsheet_batch_2026_07.sql`
6. `fix_batch_2026_07_26.sql`

Every one of them ends with a verification query. Run it.

Each was written because a fund was carrying a number that was not what the app
believed it to be: a quarterly return sitting in `current_rate`, a yield on a
fund that publishes prices, a currency on the wrong row. The pattern behind all
of them is in `0074_fund_return_basis.sql`.
