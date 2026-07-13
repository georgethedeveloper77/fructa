-- 0059_mystocks_source.sql
--
-- afx is retired. mystocks is the NSE price source.
--
-- afx blocks datacenter IP ranges. Four attempts, two networks (Supabase
-- eu-central-1 and a GitHub Actions runner), three clients (Deno fetch with a
-- bot user agent, Deno fetch with a Chrome user agent, and real Chromium via
-- Playwright). Every one of them hung until the socket died. Never a 403, never
-- a 429, never a challenge page. A refusal has a status code; a hang is a
-- firewall dropping packets.
--
-- mystocks was picked ON EVIDENCE, probed from the exact runner that scrapes it:
-- HTTP 200 in 1.9s, no auth wall, 30 of 30 known tickers, and SCOM at 35.05,
-- which is the same price afx quoted. Two independent sources agreeing.
--
-- Park afx in a long cooldown rather than deleting the row. If it ever opens up
-- again the history is worth having, and a deleted row would just get recreated
-- as a fresh unknown on the next failure.
insert into public.source_health (source, consecutive_failures, blocked_until, last_error)
values (
  'afx-nse', 5, '2099-01-01',
  'Blocks datacenter IPs. Four attempts, two networks, three clients, always silence and never a status code. Retired in favour of mystocks-nse.'
)
on conflict (source) do update set
  consecutive_failures = 5,
  blocked_until        = '2099-01-01',
  last_error           = excluded.last_error,
  updated_at           = now();

insert into public.source_health (source)
values ('mystocks-nse')
on conflict (source) do nothing;
