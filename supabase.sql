-- Bolão da Lucena 2026 - Supabase seguro para GitHub/Vercel
-- Rode este arquivo em Supabase > SQL Editor > New query > Run.
-- Este SQL NÃO usa a chave secreta/service_role. No site, use apenas URL pública + publishable/anon key.

create extension if not exists pgcrypto;

create or replace function public.unaccent_safe(input text)
returns text
language sql
immutable
as $$
  select translate(
    coalesce(input,''),
    'ÁÀÂÃÄáàâãäÉÈÊËéèêëÍÌÎÏíìîïÓÒÔÕÖóòôõöÚÙÛÜúùûüÇçÑñ',
    'AAAAAaaaaaEEEEeeeeIIIIiiiiOOOOOoooooUUUUuuuuCcNn'
  );
$$;

create table if not exists public.bolao_palpites (
  id uuid primary key default gen_random_uuid(),
  codigo text not null unique,
  game_id text not null check (game_id in ('bra-mar','bra-hai','sco-bra')),
  game_title text not null,
  game_date text not null,
  nome text not null,
  nome_norm text generated always as (lower(public.unaccent_safe(trim(nome)))) stored,
  matricula text not null,
  matricula_norm text generated always as (regexp_replace(lower(trim(matricula)), '[^0-9a-z]', '', 'g')) stored,
  setor text not null,
  score_a int not null check (score_a >= 0 and score_a <= 30),
  score_b int not null check (score_b >= 0 and score_b <= 30),
  scorer text not null,
  created_at timestamptz not null default now(),
  unique (game_id, matricula_norm),
  unique (game_id, nome_norm, matricula_norm)
);

create table if not exists public.bolao_resultados (
  game_id text primary key check (game_id in ('bra-mar','bra-hai','sco-bra')),
  official_a int not null check (official_a >= 0 and official_a <= 30),
  official_b int not null check (official_b >= 0 and official_b <= 30),
  scorers text not null default '',
  scorers_norm text[] not null default '{}',
  saved_at timestamptz not null default now()
);

create table if not exists public.bolao_admin_config (
  id int primary key default 1,
  senha_hash text not null,
  updated_at timestamptz not null default now(),
  constraint only_one_row check (id = 1)
);

-- Hash da senha administrativa gerado fora do front-end. A senha não fica no index.html.
-- Para trocar a senha depois, rode: update public.bolao_admin_config set senha_hash = crypt('NOVA_SENHA', gen_salt('bf')) where id = 1;
insert into public.bolao_admin_config (id, senha_hash)
values (1, '$1$b0L26Pwd$SI6hQ3TU2Dqc5NBQHZAKE0')
on conflict (id) do nothing;

create or replace function public.bolao_normalizar_array(nomes text)
returns text[]
language sql
immutable
as $$
  select coalesce(array_agg(trim(lower(public.unaccent_safe(x)))) filter (where trim(x) <> ''), '{}')
  from regexp_split_to_table(coalesce(nomes,''), ',') as x;
$$;

create or replace function public.bolao_salvar_resultado(
  p_senha text,
  p_game_id text,
  p_a int,
  p_b int,
  p_scorers text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_hash text;
begin
  select senha_hash into v_hash from public.bolao_admin_config where id = 1;
  if v_hash is null or crypt(p_senha, v_hash) <> v_hash then
    raise exception 'Senha inválida';
  end if;

  insert into public.bolao_resultados (game_id, official_a, official_b, scorers, scorers_norm, saved_at)
  values (p_game_id, p_a, p_b, coalesce(p_scorers,''), public.bolao_normalizar_array(p_scorers), now())
  on conflict (game_id) do update set
    official_a = excluded.official_a,
    official_b = excluded.official_b,
    scorers = excluded.scorers,
    scorers_norm = excluded.scorers_norm,
    saved_at = now();
end;
$$;

create or replace function public.bolao_validar_admin(p_senha text)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_hash text;
begin
  select senha_hash into v_hash from public.bolao_admin_config where id = 1;
  return v_hash is not null and crypt(p_senha, v_hash) = v_hash;
end;
$$;

alter table public.bolao_palpites enable row level security;
alter table public.bolao_resultados enable row level security;
alter table public.bolao_admin_config enable row level security;

-- Leitura pública dos palpites e resultados para a tela de acompanhamento.
drop policy if exists "palpites_select_publico" on public.bolao_palpites;
create policy "palpites_select_publico" on public.bolao_palpites
for select to anon, authenticated using (true);

drop policy if exists "resultados_select_publico" on public.bolao_resultados;
create policy "resultados_select_publico" on public.bolao_resultados
for select to anon, authenticated using (true);

-- Cadastro público de palpite. As travas principais são:
-- 1) RLS só permite insert;
-- 2) unique(game_id, matricula_norm) impede matrícula duplicada por jogo;
-- 3) checks impedem placares absurdos e jogos fora da lista.
-- Observação: a janela 08h-12h também é bloqueada no front-end. Para bloqueio 100% no banco,
-- use Edge Function ou uma tabela de jogos + função de cadastro com validação de horário do servidor.
drop policy if exists "palpites_insert_publico" on public.bolao_palpites;
create policy "palpites_insert_publico" on public.bolao_palpites
for insert to anon, authenticated with check (true);

-- Não há policy pública de update/delete para palpites nem de insert/update direto para resultados.
-- O resultado oficial só entra pela função bolao_salvar_resultado com senha.
revoke all on table public.bolao_admin_config from anon, authenticated;
grant usage on schema public to anon, authenticated;
grant select, insert on public.bolao_palpites to anon, authenticated;
grant select on public.bolao_resultados to anon, authenticated;
grant execute on function public.bolao_salvar_resultado(text,text,int,int,text) to anon, authenticated;
grant execute on function public.bolao_validar_admin(text) to anon, authenticated;
