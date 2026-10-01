-- Live updates for chat, Gist, news and connection requests. Realtime respects each table's RLS.
alter publication supabase_realtime add table public.messages, public.posts, public.news, public.connections;
