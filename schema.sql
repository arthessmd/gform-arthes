-- Jalankan di Supabase (project gform arthes) > SQL Editor. Aman dijalankan ulang.
create table if not exists forms(id uuid primary key default gen_random_uuid(), title text not null, event_date date, description text default '', quota int default 0, is_open boolean default true, created_at timestamptz default now());
create table if not exists registrations(id uuid primary key default gen_random_uuid(), form_id uuid references forms on delete cascade, team_name text, leader text, whatsapp text, leader_game_id text, players text[] default '{}', substitutes text[] default '{}', created_at timestamptz default now());
do $$ declare t text; begin foreach t in array array['forms','registrations'] loop
 execute format('alter table %I enable row level security', t);
 execute format('drop policy if exists "akses terbuka" on %I', t);
 execute format('create policy "akses terbuka" on %I for all to anon, authenticated using (true) with check (true)', t);
end loop; end $$;

-- ===== Link sekali pakai =====
create table if not exists invites(id uuid primary key default gen_random_uuid(), form_id uuid references forms on delete cascade, code text unique not null, label text, used boolean default false, used_at timestamptz, registration_id uuid, created_at timestamptz default now());
alter table invites enable row level security;
drop policy if exists "akses terbuka" on invites;
create policy "akses terbuka" on invites for all to anon, authenticated using (true) with check (true);

create or replace function check_invite(p_code text) returns json language plpgsql security definer as $$
declare inv invites%rowtype; f forms%rowtype; n int; s text := 'ok';
begin
 select * into inv from invites where code = p_code;
 if not found then return json_build_object('status','invalid'); end if;
 select * into f from forms where id = inv.form_id;
 select count(*) into n from registrations where form_id = f.id;
 if inv.used then s := 'used'; elsif not f.is_open then s := 'closed'; elsif f.quota > 0 and n >= f.quota then s := 'full'; end if;
 return json_build_object('status',s,'title',f.title,'description',f.description,'quota',f.quota,'count',n);
end $$;

create or replace function submit_registration(p_code text, p_team text, p_leader text, p_wa text, p_gid text, p_players text[], p_subs text[]) returns text language plpgsql security definer as $$
declare inv invites%rowtype; f forms%rowtype; n int; rid uuid;
begin
 select * into inv from invites where code = p_code for update;
 if not found then return 'invalid'; end if;
 if inv.used then return 'used'; end if;
 select * into f from forms where id = inv.form_id;
 if not f.is_open then return 'closed'; end if;
 select count(*) into n from registrations where form_id = f.id;
 if f.quota > 0 and n >= f.quota then return 'full'; end if;
 if exists(select 1 from registrations where form_id = f.id and lower(team_name) = lower(p_team)) then return 'duplicate'; end if;
 insert into registrations(form_id,team_name,leader,whatsapp,leader_game_id,players,substitutes) values (f.id,p_team,p_leader,p_wa,p_gid,p_players,p_subs) returning id into rid;
 update invites set used = true, used_at = now(), registration_id = rid where id = inv.id;
 return 'ok';
end $$;
grant execute on function check_invite(text) to anon, authenticated;
grant execute on function submit_registration(text,text,text,text,text,text[],text[]) to anon, authenticated;
-- Link satu kali pakai
create table if not exists invites(id uuid primary key default gen_random_uuid(), form_id uuid references forms on delete cascade, token text unique not null, used boolean default false, used_at timestamptz, team_name text, created_at timestamptz default now());
alter table invites enable row level security;
drop policy if exists "akses terbuka" on invites;
create policy "akses terbuka" on invites for all to anon, authenticated using (true) with check (true);
