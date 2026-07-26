-- cytonn_chyf_yield_basis.sql
--
-- Cytonn High Yield Fund, `cytonn-sp-kes`. Run after 0074/0075. Rebuild snapshot.
--
-- Source: CHYF Fund Fact Sheet, AUGUST 2025, fetched from
-- https://cytonn.com/uploads/downloads/chyf-fact-sheet-aug-25.pdf
--
--
-- WHAT THIS FILE IS ACTUALLY ABOUT
--
-- The brief for this fund arrived as a search-engine summary rather than a
-- fact sheet. It contained six figures. Not one of them was publishable, and
-- the real number was on none of them:
--
--   "targets 14.0% p.a."                    a target, said so
--   "14% to over 20% depending on           a marketing range, not a figure
--    performance"
--   "target rate of return is 14-15% p.a."  a target, from Cytonn's own FAQ
--   "11.35% effective annual rate"          the CYTONN MONEY MARKET FUND.
--                                           A different fund entirely.
--   "13.93% as of 31st October"             a Facebook post, year unstated
--   "13% to 14%+ p.a. range"                NOT PUBLISHED ANYWHERE. It was
--                                           reasoned out by the summariser
--                                           from "CHYF is specialised, so its
--                                           yield historically outpaces the
--                                           money market rate". An inference
--                                           wearing the clothes of a quote.
--
-- The fact sheet says the fund returned 21.9% p.a. in August 2025.
--
-- So the summary was not merely unsourced. It was wrong by eight percentage
-- points, and every one of its figures was low enough to look plausible. This
-- is the exact input the review gate in 0076 exists to catch, and it is worth
-- recording that the gate's hardest case so far came from a search result
-- rather than from a PDF.


-- ── 1. Basis ───────────────────────────────────────────────────────────────
--
-- Was 'nav'. It is not a priced fund and never was: the sheet quotes an
-- ANNUALIZED RETURN, footnoted as "historical percentage you can expect to earn
-- with the fund during one year of investment on the basis of the so far
-- realized monthly returns". That is a realized effective annual rate, the same
-- object a money market fund quotes, so basis is 'yield'.
--
-- This closes an open question carried since an earlier session, which had this
-- fund flagged as "DB says nav, sheet only prints an annualized return, reads
-- like a yield fund". It reads like one because it is one.

update public.funds set
  basis          = 'yield',
  net_of         = 'fees',
  fee_kind       = 'mgmt',
  mgmt_fee       = 2.00,
  min_invest     = 100000,
  top_up_min     = 10000,
  lock_in_months = 3,
  inception_date = date '2019-10-07',
  objective      = 'A high level of current income while protecting capital, outperforming the yield available from commercial banks through real estate backed and other alternative instruments.',
  withdraw_note  = 'Redeemable any time after the initial 3 month holding period'
where id = 'cytonn-sp-kes';


-- ── 2. One dated rate point, and NO current_rate ───────────────────────────
--
-- 21.9% p.a., August 2025. Real, published, and eleven months old.
--
-- It goes into rate_history, where it carries its date and can never be read as
-- today's figure. It does NOT go into current_rate, and that restraint is the
-- whole point: 21.9% would top every fund in the country on the Markets list,
-- with no date beside it, on the strength of a sheet from last August.
--
-- This is the Old Mutual rule applied to an empty field rather than a stale
-- one. The fund currently shows no rate. After this it still shows no rate,
-- because "we do not know what this fund is paying now" is true, and a
-- year-old number presented as current is not.
--
-- current_rate gets set the moment a 2026 sheet arrives. Until then the honest
-- state is a dash.

insert into public.rate_history (fund_id, as_of, rate, source) values
  ('cytonn-sp-kes', date '2025-08-31', 21.90, 'cytonn-factsheet-2025-08')
on conflict do nothing;

update public.funds set source_type = 'manual' where id = 'cytonn-sp-kes';


-- ── 3. Custody ─────────────────────────────────────────────────────────────

update public.companies c set
  trustee   = coalesce(c.trustee,   'Goal Advisory'),
  custodian = coalesce(c.custodian, 'SBM Bank Kenya Ltd'),
  phone     = coalesce(c.phone,     '+254709101200'),
  email     = coalesce(c.email,     'sales@cytonn.com'),
  website   = coalesce(c.website,   'https://cytonn.com')
from public.funds f
where f.id = 'cytonn-sp-kes' and c.id = f.company_id;


-- ── 4. Register the source, with the pattern ───────────────────────────────
--
-- Cytonn's fact sheet filenames are fully predictable:
--
--   https://cytonn.com/uploads/downloads/chyf-fact-sheet-{mon}-{yy}.pdf
--
-- Confirmed against aug-25, aug-23, jul-24, mar-24 and aug-24. That makes this
-- the first source in the table Phase 3 can walk without scraping a listing
-- page at all: it can construct the URL for a given month and try it.

insert into public.factsheet_sources
  (id, company_id, listing_url, direct_url, link_pattern, cadence, notes)
select 'cytonn-chyf', f.company_id,
       'https://cytonn.com/high-yield-fund',
       'https://cytonn.com/uploads/downloads/chyf-fact-sheet-aug-25.pdf',
       'chyf-fact-sheet-([a-z]{3})-(\d{2})\.pdf',
       'monthly',
       'Filename is constructible: chyf-fact-sheet-{mon}-{yy}.pdf. Newest reachable was aug-25.'
from public.funds f where f.id = 'cytonn-sp-kes'
on conflict (id) do nothing;


-- ── Flags ──────────────────────────────────────────────────────────────────
--
-- STALE, AND FETCHABLE. Try chyf-fact-sheet-jun-26.pdf and work backwards.
-- Anything from 2026 supersedes everything here and unblocks current_rate.
--
-- MINIMUM INVESTMENT IS CONTRADICTED BY CYTONN'S OWN SITE. The product page and
-- the August 2025 fact sheet both say Kshs 100,000. The FAQ page says Kshs
-- 1,000,000. Two sources to one, and the fact sheet is the more formal
-- document, so 100,000 is written. Worth confirming, because a tenfold error in
-- either direction changes who this fund is for.
--
-- NET OF FEES IS AN ASSUMPTION, not a quote. The sheet states a 2.0% annual
-- management fee and a 21.9% return without saying whether one is inside the
-- other. Every other Kenyan manager in the database quotes net of fees and
-- gross of withholding tax, so that is what is written, and it should be
-- confirmed rather than trusted.
--
-- ASSET ALLOCATION not stored, for the fifth time: real estate backed notes
-- 74.3%, fixed and demand deposits 24.8%, cash 0.8%. This one is the clearest
-- argument yet for the missing column, because a fund three quarters invested
-- in real estate backed notes is a materially different proposition from its
-- peers and the app currently has no way to say so.
--
-- A NAME TO BE CAREFUL WITH. Cytonn operates both the Cytonn High Yield FUND
-- (CHYF), the CMA-regulated collective investment scheme this row describes,
-- and Cytonn High Yield SOLUTIONS (CHYS), a limited liability partnership.
-- Cytonn's own FAQ page carries, alongside the CHYF material, a creditor
-- repayment schedule referencing an Official Receiver and funds described as
-- currently illiquid. That material is about the LLP structures and not about
-- this CIS, but the names differ by one word and the app would be putting this
-- fund in front of people choosing where to put their savings. Worth your own
-- diligence on which vehicle is which before this one is featured, ranked
-- highly, or pushed in an alert.
