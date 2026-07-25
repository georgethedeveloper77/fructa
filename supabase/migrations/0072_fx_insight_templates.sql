-- 0072_fx_insight_templates.sql
--
-- The currency card's copy bank, seeded into the table that already exists.
--
-- No new table and no new admin surface. The keys namespace under `fx.` so
-- they can never collide with a fund signal key, and signal_engine.dart looks
-- funds up by a different key set, so the two banks share storage without
-- sharing behaviour.
--
-- KEY SHAPE, built by FxEngine.copyKey in lib/engine/fx_engine.dart:
--
--     fx.<stance>.<regime>.<band>      buying and holding
--     fx.<stance>.<regime>             hedged, which has no hurdle
--
--   stance  buying    holds KES, would convert in. Crosses the spread twice.
--           holding   holds USD, spends KES. Exit spread cancels.
--           hedged    holds and spends USD. No position to take.
--
--   regime  calm        twelve month move inside two percent
--           drifting    steady one way move that has not covered the hurdle
--           falling     shilling down eight percent or more over the year
--           snapback    shilling up five percent or more over three months
--
--   band    low   under 4% a year        mod   4 to 8%        high   over 8%
--
-- That gives 12 + 12 + 4 = 28 slots, two phrasings each. The app picks the
-- slot from live market state and the phrasing from the day of the year, so
-- the line moves with the market rather than at random and stays put for a
-- whole day. Randomising per rebuild would give a different sentence every
-- time the widget repainted, which on a screen full of numbers reads as a bug.
--
-- TOKENS, filled app-side in lib/core/insights/fx_copy.dart:
--   {mean}    current indicative mean, e.g. 129.20
--   {be}      breakeven rate for this stance and horizon, e.g. 136.03
--   {hurdle}  that breakeven as an annualised percent, e.g. 5.3
--   {gap}     annual net yield gap in points, e.g. 5.5
--   {mv12}    twelve month move in the pair, percent, positive = KES weaker
--   {mv3}     three month move, same sign convention
-- <b> is honoured by core/widgets/markup.dart, as in the fund signal bank.
--
-- TAG. Every row is NOTE. The tag drives colour in the signal UI, where
-- STRENGTH and WATCH are judgements about a fund. Currency copy is context,
-- not a verdict, and a green STRENGTH chip beside "the shilling has fallen
-- 11%" would be the app taking a side on a trade it should only be pricing.
--
-- Data only, no schema change. Idempotent via the existing unique (key,
-- template), so re-running finds nothing to insert.

insert into public.insight_templates (key, tag, template) values

-- ── BUYING USD ────────────────────────────────────────────────────────────
('fx.buying.calm.low','NOTE',$t$The pair is sitting still and the yield gap is narrow. Buying USD needs <b>{be}</b> inside a year, about <b>{hurdle}%</b>.$t$),
('fx.buying.calm.low','NOTE',$t$A quiet market and only <b>{gap} points</b> between the two funds. The bar for converting in is {be}.$t$),
('fx.buying.calm.mod','NOTE',$t$Flat near <b>{mean}</b>. Buying USD has to clear <b>{hurdle}% a year</b> before the spread and the yield gap are paid off.$t$),
('fx.buying.calm.mod','NOTE',$t$Every month the pair holds at {mean}, a KES fund banks another slice of the <b>{gap} point</b> gap.$t$),
('fx.buying.calm.high','NOTE',$t$A wide <b>{gap} point</b> gap against a still market. Buying USD needs <b>{be}</b> within the year just to draw level.$t$),
('fx.buying.calm.high','NOTE',$t$The hurdle is <b>{hurdle}% a year</b> and the pair is not moving. That is the whole trade.$t$),

('fx.buying.drifting.low','NOTE',$t$The pair has moved <b>{mv12}%</b> over the year against a <b>{hurdle}%</b> bar. Closer to break even than it usually is.$t$),
('fx.buying.drifting.low','NOTE',$t$A slow slide and a narrow gap. Converting in needs <b>{be}</b>, and the pair has covered {mv12}% in twelve months.$t$),
('fx.buying.drifting.mod','NOTE',$t$The shilling is drifting, <b>{mv12}%</b> over the year. Buying USD still needs <b>{hurdle}% a year</b> to pay for itself.$t$),
('fx.buying.drifting.mod','NOTE',$t$At this pace the pair reaches <b>{be}</b> later than the twelve months the comparison assumes.$t$),
('fx.buying.drifting.high','NOTE',$t$A <b>{mv12}%</b> year against a <b>{hurdle}%</b> hurdle. The drift is real and it is not yet enough.$t$),
('fx.buying.drifting.high','NOTE',$t$The gap is <b>{gap} points</b> wide. A drifting shilling closes it slowly, and the spread is charged whether it closes or not.$t$),

('fx.buying.falling.low','NOTE',$t$Down <b>{mv12}%</b> in twelve months, well past the <b>{hurdle}%</b> a buyer needed. That is history, not a forecast.$t$),
('fx.buying.falling.low','NOTE',$t$The pair has cleared the bar this year. It has also given moves like this back inside a quarter.$t$),
('fx.buying.falling.mod','NOTE',$t$A <b>{mv12}%</b> fall has carried past the <b>{hurdle}%</b> hurdle. Every buyer converting today starts again at <b>{be}</b>.$t$),
('fx.buying.falling.mod','NOTE',$t$Last year cleared it. The question the page answers is what the next one has to do from <b>{mean}</b>.$t$),
('fx.buying.falling.high','NOTE',$t$Down <b>{mv12}%</b> against a <b>{hurdle}%</b> bar, so the currency is doing the work the <b>{gap} point</b> yield gap cannot.$t$),
('fx.buying.falling.high','NOTE',$t$A wide yield gap and a falling shilling pull in opposite directions. The crossing point is <b>{be}</b>.$t$),

('fx.buying.snapback.low','NOTE',$t$The shilling has gained <b>{mv3}%</b> in three months. Anyone who bought USD before that is behind before yield is counted.$t$),
('fx.buying.snapback.low','NOTE',$t$A sharp recovery, and a narrow <b>{gap} point</b> gap. Converting in needs <b>{be}</b> from here.$t$),
('fx.buying.snapback.mod','NOTE',$t$Up <b>{mv3}%</b> in a quarter. Buying USD now starts from <b>{mean}</b> and still needs <b>{hurdle}% a year</b>.$t$),
('fx.buying.snapback.mod','NOTE',$t$Recoveries this fast are why the hurdle is priced rather than assumed away.$t$),
('fx.buying.snapback.high','NOTE',$t$A <b>{mv3}%</b> quarter against the dollar, with a <b>{gap} point</b> yield gap on top. Both are working against a buyer.$t$),
('fx.buying.snapback.high','NOTE',$t$The shilling is stronger and the KES fund pays <b>{gap} points</b> more. Converting in needs <b>{be}</b>.$t$),

-- ── HOLDING USD ───────────────────────────────────────────────────────────
('fx.holding.calm.low','NOTE',$t$You are past the buy spread, so only the <b>{gap} point</b> gap is left. Staying long needs <b>{be}</b>.$t$),
('fx.holding.calm.low','NOTE',$t$A narrow gap and a still market. Converting now buys you <b>{hurdle}% a year</b> of head start.$t$),
('fx.holding.calm.mod','NOTE',$t$Flat at <b>{mean}</b>. A KES fund pays you <b>{hurdle}% a year</b> to convert now, and the pair has to reach {be} to make waiting right.$t$),
('fx.holding.calm.mod','NOTE',$t$Holding dollars in a still market costs the <b>{gap} point</b> gap and buys protection you may not need.$t$),
('fx.holding.calm.high','NOTE',$t$A <b>{gap} point</b> gap is a lot to give up to a market that is not moving. Break even is <b>{be}</b>.$t$),
('fx.holding.calm.high','NOTE',$t$Converting now is worth <b>{hurdle}% a year</b> while the pair sits at {mean}. That is the price of waiting.$t$),

('fx.holding.drifting.low','NOTE',$t$The pair has moved <b>{mv12}%</b> over the year against a <b>{hurdle}%</b> bar. Holding is close to paying for itself.$t$),
('fx.holding.drifting.low','NOTE',$t$A narrow gap and a drifting shilling. This is the case where waiting costs least.$t$),
('fx.holding.drifting.mod','NOTE',$t$The pair has moved <b>{mv12}%</b> in twelve months and needs <b>{hurdle}%</b> for holding to win. Closer than it looks, not there.$t$),
('fx.holding.drifting.mod','NOTE',$t$Drifting toward <b>{be}</b> but not yet at it. Converting now still banks the <b>{gap} point</b> gap.$t$),
('fx.holding.drifting.high','NOTE',$t$A <b>{gap} point</b> gap against a <b>{mv12}%</b> drift. The yield is winning that race today.$t$),
('fx.holding.drifting.high','NOTE',$t$Waiting needs <b>{hurdle}% a year</b> and the pair is giving you {mv12}%. The shortfall is the cost.$t$),

('fx.holding.falling.low','NOTE',$t$Down <b>{mv12}%</b> against a <b>{hurdle}%</b> bar. Holding dollars has been the right call this year.$t$),
('fx.holding.falling.low','NOTE',$t$The pair cleared the bar comfortably. From <b>{mean}</b> it has to do it again, and that is a separate question.$t$),
('fx.holding.falling.mod','NOTE',$t$A <b>{mv12}%</b> fall has beaten the <b>{hurdle}%</b> needed. Holding won the last year; the next one restarts at <b>{be}</b>.$t$),
('fx.holding.falling.mod','NOTE',$t$Waiting paid this year. The record below shows how often it has, and how often it has not.$t$),
('fx.holding.falling.high','NOTE',$t$Even a <b>{gap} point</b> yield gap has not kept up with a <b>{mv12}%</b> fall. Break even from here is <b>{be}</b>.$t$),
('fx.holding.falling.high','NOTE',$t$The currency has outrun the yield this year. That is the case for holding, and it is the case that reverses fastest.$t$),

('fx.holding.snapback.low','NOTE',$t$Up <b>{mv3}%</b> in three months. Holding dollars has just cost more than the <b>{gap} point</b> gap ever would.$t$),
('fx.holding.snapback.low','NOTE',$t$A sharp recovery. From <b>{mean}</b> the bar for waiting is back to <b>{be}</b>.$t$),
('fx.holding.snapback.mod','NOTE',$t$The shilling has gained <b>{mv3}%</b> in a quarter, so waiting has given back more than a year of yield gap.$t$),
('fx.holding.snapback.mod','NOTE',$t$Converting now is worth <b>{hurdle}% a year</b>, and the pair has just moved <b>{mv3}%</b> the wrong way for a holder.$t$),
('fx.holding.snapback.high','NOTE',$t$A <b>{mv3}%</b> recovery on top of a <b>{gap} point</b> yield gap. Both sides of the trade moved against holding.$t$),
('fx.holding.snapback.high','NOTE',$t$Break even is <b>{be}</b> and the pair has just travelled the other way. The record below has done this before.$t$),

-- ── HEDGED ────────────────────────────────────────────────────────────────
('fx.hedged.calm','NOTE',$t$USD in and USD out means there is no currency position to take. A KES fund pays more on paper and hands you a bill that moves.$t$),
('fx.hedged.calm','NOTE',$t$Your costs are already in dollars, so a USD fund is not a bet. It is the absence of one.$t$),
('fx.hedged.drifting','NOTE',$t$The pair has moved <b>{mv12}%</b> this year and none of it touched you. That is what matching the currency buys.$t$),
('fx.hedged.drifting','NOTE',$t$Matching the currency you spend in removes the question the rest of this page is asking.$t$),
('fx.hedged.falling','NOTE',$t$Down <b>{mv12}%</b> over the year. Anyone holding a KES fund against USD costs has felt that; you have not.$t$),
('fx.hedged.falling','NOTE',$t$A falling shilling is somebody else's problem when your costs are in dollars.$t$),
('fx.hedged.snapback','NOTE',$t$The shilling has gained <b>{mv3}%</b> in a quarter. Matching your spending currency means neither direction reaches you.$t$),
('fx.hedged.snapback','NOTE',$t$Sharp moves in either direction are noise when income and costs share a currency.$t$)

on conflict (key, template) do nothing;
