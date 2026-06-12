-- CORREÇÃO FINAL DO BOTÃO "ZERAR LISTA"
-- Cole tudo no Supabase > SQL Editor e rode.
-- Não apaga os palpites automaticamente; só cria/atualiza a função.

-- 1) Garante a senha administrativa usada pelo site
insert into public.bolao_admin_config (id, senha_hash, updated_at)
values (1, '@Bolao2026!', now())
on conflict (id)
do update set
  senha_hash = excluded.senha_hash,
  updated_at = now();

-- 2) Garante a função de validação de senha
create or replace function public.bolao_validar_admin(p_senha text)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_senha text;
begin
  select senha_hash
    into v_senha
  from public.bolao_admin_config
  where id = 1;

  return coalesce(v_senha = p_senha, false);
end;
$$;

grant execute on function public.bolao_validar_admin(text) to anon;
grant execute on function public.bolao_validar_admin(text) to authenticated;

-- 3) Garante a função que o HTML chama
create or replace function public.bolao_apagar_todos_palpites(p_senha text)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_ok boolean;
begin
  select public.bolao_validar_admin(p_senha) into v_ok;

  if coalesce(v_ok, false) is not true then
    raise exception 'Senha inválida.';
  end if;

  delete from public.bolao_palpites;

  return true;
end;
$$;

grant execute on function public.bolao_apagar_todos_palpites(text) to anon;
grant execute on function public.bolao_apagar_todos_palpites(text) to authenticated;

-- 4) Força o Supabase/PostgREST a enxergar a função nova
notify pgrst, 'reload schema';

-- 5) Testes que NÃO apagam palpites
select public.bolao_validar_admin('@Bolao2026!'::text) as senha_ok;

select
  routine_schema,
  routine_name
from information_schema.routines
where routine_schema = 'public'
  and routine_name = 'bolao_apagar_todos_palpites';
