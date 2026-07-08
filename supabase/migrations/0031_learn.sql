-- Phase 4 — Learn. Admin-authored units → lessons → steps, published inside the
-- snapshot (like companies/agents/config) and read by the app cache-first. XP,
-- streak and completion live on-device; nothing here tracks a user.
--
-- A step is one of: explainer | interactive | quiz. Its shape lives in `payload`
-- (jsonb) so new step kinds don't need migrations. A lesson may carry a
-- `fund_id`: the app resolves it to the LIVE rate for the "live term" badge and
-- the "See it live" hand-off, so lessons never hard-code a number that goes
-- stale.

create table if not exists learn_units (
  id           text primary key,
  ord          int  not null default 0,
  title        text not null,
  subtitle     text,
  accent       text,                                   -- optional visual hint: gold|sky|emerald|iris|amber
  unlock_after text references learn_units(id),        -- null = open from the start
  active       boolean not null default true
);

create table if not exists learn_lessons (
  id       text primary key,
  unit_id  text not null references learn_units(id) on delete cascade,
  ord      int  not null default 0,
  title    text not null,
  xp       int  not null default 20,
  fund_id  text,                                        -- optional live-term link
  active   boolean not null default true
);

create table if not exists learn_steps (
  id         text primary key,
  lesson_id  text not null references learn_lessons(id) on delete cascade,
  ord        int  not null default 0,
  kind       text not null,                             -- explainer | interactive | quiz
  payload    jsonb not null default '{}'::jsonb
);

create index if not exists learn_lessons_unit_idx on learn_lessons(unit_id, ord);
create index if not exists learn_steps_lesson_idx on learn_steps(lesson_id, ord);

-- Published via the service-role snapshot builder; edited via the service-role
-- admin. The app never reads these tables directly (it reads the snapshot), so
-- RLS is on with no policies — anon/authenticated can't touch them.
alter table learn_units   enable row level security;
alter table learn_lessons enable row level security;
alter table learn_steps   enable row level security;

-- ── Seed: Unit 1 (Money basics) + Unit 2 (Reading a rate) ───────────────────

insert into learn_units (id, ord, title, subtitle, accent, unlock_after) values
  ('u_basics', 0, 'Money basics', 'What a fund is, and what it pays you.', 'gold', null),
  ('u_rate',   1, 'Reading a rate', 'What the number means, before and after tax.', 'sky', 'u_basics')
on conflict (id) do nothing;

insert into learn_lessons (id, unit_id, ord, title, xp, fund_id) values
  ('l_what_mmf',   'u_basics', 0, 'What is a money market fund?', 20, null),
  ('l_yield_ret',  'u_basics', 1, 'Yield vs return',              20, null),
  ('l_gross_net',  'u_rate',   0, 'Gross vs net',                 20, null),
  ('l_rate_means', 'u_rate',   1, 'What 10.67% means',            40, null),
  ('l_tax_bite',   'u_rate',   2, 'The 15% tax bite',             30, null)
on conflict (id) do nothing;

insert into learn_steps (id, lesson_id, ord, kind, payload) values
  ('s_mmf_0', 'l_what_mmf', 0, 'explainer', $j${"title":"What is a money market fund?","body":"A money market fund (MMF) pools many people's cash and lends it short-term — to banks, the government, and solid companies. You can add or withdraw almost any time.\n\nInstead of one big risky bet, your money sits across lots of safe, short loans. In return you earn a yield, quoted as a percent per year.","note":"MMFs are among the lowest-risk ways to earn in Kenya — but low risk is not no risk."}$j$::jsonb),
  ('s_mmf_1', 'l_what_mmf', 1, 'quiz', $j${"prompt":"What does a money market fund mainly do with your money?","options":[{"text":"Buys shares on the NSE and hopes they rise","correct":false},{"text":"Lends it short-term to banks, government and companies","correct":true},{"text":"Locks it away for a fixed number of years","correct":false}],"explain_ok":"Right — MMFs hold short-term debt, which is why they stay liquid and low-risk.","explain_no":"Not quite — an MMF lends short-term (not shares, not a long lock-in). That's what keeps it liquid."}$j$::jsonb),

  ('s_yr_0', 'l_yield_ret', 0, 'explainer', $j${"title":"Yield vs return","body":"A yield is a rate — a percent per year, like 10.67%. It tells you the pace your money grows at.\n\nA return is an amount — the actual shillings you earned over a period. Two people in the same fund earn the same yield, but very different returns if one put in more.","note":"Compare funds by yield (the rate). Judge your own progress by return (the shillings)."}$j$::jsonb),
  ('s_yr_1', 'l_yield_ret', 1, 'quiz', $j${"prompt":"Two friends are in the same MMF at 11%. One earns more shillings than the other. Why?","options":[{"text":"Their yields are different","correct":false},{"text":"They put in different amounts","correct":true},{"text":"One of them is being cheated","correct":false}],"explain_ok":"Exactly — same yield, bigger base, bigger return in shillings.","explain_no":"Same fund means the same yield. The difference is how much each put in."}$j$::jsonb),

  ('s_gn_0', 'l_gross_net', 0, 'explainer', $j${"title":"Gross vs net","body":"A gross rate is before costs. A net rate is what actually reaches you.\n\nFor Kenyan MMFs the quoted rate is already net of the fund's management fee, but before the 15% withholding tax (WHT). So the honest number to compare is the after-tax, or net, yield.","note":"fructa shows the net rate too, so you compare like with like."}$j$::jsonb),
  ('s_gn_1', 'l_gross_net', 1, 'quiz', $j${"prompt":"A fund quotes 11%. What's still taken off before it's truly yours?","options":[{"text":"The 15% withholding tax","correct":true},{"text":"The management fee (again)","correct":false},{"text":"Nothing — 11% is what you get","correct":false}],"explain_ok":"Right — the quote is net of fees but before the 15% WHT.","explain_no":"The fee is already out; it's the 15% withholding tax that's still to come."}$j$::jsonb),

  ('s_rm_0', 'l_rate_means', 0, 'explainer', $j${"title":"What does 10.67% actually mean?","body":"It's the effective annual yield — roughly what your money grows by over a year if the rate holds. It's already net of the fund's fee, but before the 15% withholding tax.\n\nSo KES 10,000 left in for a year earns about KES 1,067 — and you keep about KES 907 after tax.","note":"fructa always shows the latest published rate and the date it's from — never a stale number dressed up as today's."}$j$::jsonb),
  ('s_rm_1', 'l_rate_means', 1, 'interactive', $j${"title":"Move the amount","body":"See what 10.67% earns in a year, after the 15% tax.","widget":"earn_slider","rate":10.67,"min":1000,"max":500000,"initial":10000}$j$::jsonb),
  ('s_rm_2', 'l_rate_means', 2, 'quiz', $j${"prompt":"On KES 50,000 at 10.67% for a year, what do you roughly keep after tax?","options":[{"text":"KES 5,335 — the full 10.67%","correct":false},{"text":"About KES 4,535 — after the 15% tax","correct":true},{"text":"KES 50,000 — rates don't add money","correct":false}],"explain_ok":"Right — 10.67% of 50,000 is ~5,335, and you keep 85% after withholding tax.","explain_no":"Not quite — the rate is before tax; 15% is withheld, so about KES 4,535 is yours."}$j$::jsonb),

  ('s_tax_0', 'l_tax_bite', 0, 'explainer', $j${"title":"The 15% tax bite","body":"On MMF and most interest, Kenya withholds 15% before you ever see it — the fund pays it for you. That's why the after-tax number is lower than the headline.\n\nOne exception: infrastructure bonds are tax-free, so their headline is already what you keep.","note":"Tax-free doesn't automatically mean better — always compare on the net yield."}$j$::jsonb),
  ('s_tax_1', 'l_tax_bite', 1, 'quiz', $j${"prompt":"Which of these usually pays interest with NO withholding tax?","options":[{"text":"A money market fund","correct":false},{"text":"A Treasury bill","correct":false},{"text":"An infrastructure bond","correct":true}],"explain_ok":"Right — infrastructure bonds are tax-free, which lifts their effective return.","explain_no":"MMFs and T-bills are taxed at 15%. Infrastructure bonds are the tax-free case."}$j$::jsonb)
on conflict (id) do nothing;
