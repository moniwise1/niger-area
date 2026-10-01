-- Niger Area: advance the game one day at midnight West Africa Time (23:00 UTC).
create extension if not exists pg_cron;

select cron.schedule('niger-area-daily-tick', '0 23 * * *', $$ select public.advance_day(); $$);
