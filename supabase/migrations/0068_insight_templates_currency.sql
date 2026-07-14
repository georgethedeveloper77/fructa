-- 0057_insight_templates_currency.sql
--
-- The minimum-ticket signal templates hardcode the currency:
--
--     'Entry needs <b>KES {min}</b>  the steepest minimum in the set.'
--
-- but {min} is filled from funds.min_invest, which is denominated in the fund's
-- OWN currency. On a fund whose minimum is USD 100, that renders "KES 100": a
-- correct number under a wrong currency, which is worse than no signal at all.
--
-- signal_engine.dart now fills {min} with the amount AND its currency
-- ("USD 100" / "KES 1,000"), so the literal prefix in the template has to go.
-- The in-code fallback bank is fixed in the same delivery; this brings the
-- admin-editable bank in the database into line with it.
--
-- Data only. No schema change. Idempotent: re-running finds nothing to replace.

update insight_templates
set    template = replace(template, 'KES {min}', '{min}')
where  template like '%KES {min}%';
