-- Jalankan di Supabase (project gform arthes) > SQL Editor. Aman dijalankan ulang.
create table if not exists forms(id uuid primary key default gen_random_uuid(), title text not null, event_date date, description text default '', quota int default 0, is_open boolean default true, created_at timestamptz default now());
create table if not exists registrations(id uuid primary key default gen_random_uuid(), form_id uuid references forms on delete cascade, team_name text, leader text, whatsapp text, leader_game_id text, players text[] default '{}', substitutes text[] default '{}', created_at timestamptz default now());
do $$ declare t text; begin foreach t in array array['forms','registrations'] loop
 execute format('alter table %I enable row level security', t);
 execute format('drop policy if exists "akses terbuka" on %I', t);
 execute format('create policy "akses terbuka" on %I for all to anon, authenticated using (true) with check (true)', t);
end loop; end $$;
