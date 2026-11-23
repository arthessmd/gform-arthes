-- Jalankan di Supabase (project gform arthes) > SQL Editor. Aman dijalankan ulang (idempotent).
-- Mendukung pendaftaran TIM dan SOLO per tanggal, dengan link sekali pakai.

-- ===== Tabel dasar =====
create table if not exists forms(id uuid primary key default gen_random_uuid(), title text not null, event_date date, description text default '', quota int default 0, is_open boolean default true, created_at timestamptz default now());
create table if not exists registrations(id uuid primary key default gen_random_uuid(), form_id uuid references forms on delete cascade, team_name text, leader text, whatsapp text, leader_game_id text, players text[] default '{}', substitutes text[] default '{}', created_at timestamptz default now());
create table if not exists invites(id uuid primary key default gen_random_uuid(), form_id uuid references forms on delete cascade, token text unique, used boolean default false, used_at timestamptz, team_name text, created_at timestamptz default now());

-- ===== Kolom baru untuk fitur SOLO =====
alter table forms        add column if not exists group_link_team text default '';    -- link grup untuk peserta tim (tampil setelah berhasil daftar)
alter table forms        add column if not exists group_link_solo text default '';    -- link grup untuk peserta solo
alter table forms        add column if not exists success_note text default '';       -- pesan tambahan di halaman berhasil
alter table forms        add column if not exists solo_quota int default 0;          -- kuota solo (0 = tanpa batas); kolom "quota" = kuota tim
alter table invites      add column if not exists kind text not null default 'team'; -- 'team' atau 'solo'
alter table invites      add column if not exists used_by text;                      -- nama tim / nama solo yang memakai link
alter table registrations add column if not exists kind text not null default 'team';
-- Untuk solo: nama -> kolom leader, ID game -> leader_game_id, WhatsApp -> whatsapp, team_name dikosongkan.

-- Bersihkan sisa skema lama (kolom "code") bila pernah terbuat
do $$ begin
  if exists(select 1 from information_schema.columns where table_name='invites' and column_name='code') then
    alter table invites alter column code drop not null;
  end if;
end $$;
update invites set used_by = team_name where used_by is null and team_name is not null;

-- ===== Akses (RLS) =====
do $$ declare t text; begin foreach t in array array['forms','registrations','invites'] loop
 execute format('alter table %I enable row level security', t);
 execute format('drop policy if exists "akses terbuka" on %I', t);
 execute format('create policy "akses terbuka" on %I for all to anon, authenticated using (true) with check (true)', t);
end loop; end $$;

-- ===== Fungsi: cek link =====
drop function if exists check_invite(text);
create or replace function check_invite(p_token text) returns json language plpgsql security definer as $$
declare inv invites%rowtype; f forms%rowtype; n int; q int; s text := 'ok';
begin
 select * into inv from invites where token = p_token;
 if not found then return json_build_object('status','invalid'); end if;
 select * into f from forms where id = inv.form_id;
 select count(*) into n from registrations where form_id = f.id and kind = inv.kind;
 q := case when inv.kind = 'solo' then coalesce(f.solo_quota,0) else coalesce(f.quota,0) end;
 if inv.used then s := 'used'; elsif not f.is_open then s := 'closed'; elsif q > 0 and n >= q then s := 'full'; end if;
 return json_build_object('status',s,'kind',inv.kind,'title',f.title,'description',f.description,'quota',q,'count',n);
end $$;

-- ===== Fungsi: kirim pendaftaran (atomik: cek link, kuota, duplikat, lalu tandai terpakai) =====
drop function if exists submit_registration(text,text,text,text,text,text[],text[]);
create or replace function submit_registration(p_token text, p_team text, p_leader text, p_wa text, p_gid text, p_players text[], p_subs text[]) returns json language plpgsql security definer as $$
declare inv invites%rowtype; f forms%rowtype; n int; q int; rid uuid; who text;
begin
 select * into inv from invites where token = p_token for update;
 if not found then return json_build_object('status','invalid'); end if;
 if inv.used then return json_build_object('status','used'); end if;
 select * into f from forms where id = inv.form_id;
 if not f.is_open then return json_build_object('status','closed'); end if;
 select count(*) into n from registrations where form_id = f.id and kind = inv.kind;
 q := case when inv.kind = 'solo' then coalesce(f.solo_quota,0) else coalesce(f.quota,0) end;
 if q > 0 and n >= q then return json_build_object('status','full'); end if;
 if inv.kind = 'solo' then
   if coalesce(trim(p_leader),'')='' or coalesce(trim(p_gid),'')='' or coalesce(trim(p_wa),'')='' then return json_build_object('status','incomplete'); end if;
   if exists(select 1 from registrations where form_id = f.id and kind = 'solo' and lower(trim(leader_game_id)) = lower(trim(p_gid))) then return json_build_object('status','duplicate'); end if;
   insert into registrations(form_id,kind,leader,whatsapp,leader_game_id) values (f.id,'solo',trim(p_leader),trim(p_wa),trim(p_gid)) returning id into rid;
   who := trim(p_leader);
 else
   if exists(select 1 from registrations where form_id = f.id and kind = 'team' and lower(team_name) = lower(p_team)) then return json_build_object('status','duplicate'); end if;
   insert into registrations(form_id,kind,team_name,leader,whatsapp,leader_game_id,players,substitutes) values (f.id,'team',p_team,p_leader,p_wa,p_gid,p_players,p_subs) returning id into rid;
   who := p_team;
 end if;
 update invites set used = true, used_at = now(), used_by = who, team_name = who where id = inv.id;
 return json_build_object('status','ok','group_link',case when inv.kind='solo' then f.group_link_solo else f.group_link_team end,'note',f.success_note);
end $$;

grant execute on function check_invite(text) to anon, authenticated;
grant execute on function submit_registration(text,text,text,text,text,text[],text[]) to anon, authenticated;
