-- Documentos: notas em texto e imagem compartilhadas com os grupos.
-- Requer as funções can_write() e is_admin() da migration dos gestores.

create table if not exists public.documents (
  id uuid primary key default gen_random_uuid(),
  title text not null default 'Documento sem título',
  content jsonb not null default '[]'::jsonb,
  shared_all boolean not null default false,
  published boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.document_groups (
  document_id uuid not null references public.documents(id) on delete cascade,
  group_id uuid not null references public.groups(id) on delete cascade,
  primary key (document_id, group_id)
);

alter table public.documents enable row level security;
alter table public.document_groups enable row level security;

drop policy if exists documents_read on public.documents;
drop policy if exists documents_write on public.documents;
create policy documents_read on public.documents
  for select to authenticated using (true);
create policy documents_write on public.documents
  for all to authenticated using (public.can_write()) with check (public.can_write());

drop policy if exists document_groups_read on public.document_groups;
drop policy if exists document_groups_write on public.document_groups;
create policy document_groups_read on public.document_groups
  for select to authenticated using (true);
create policy document_groups_write on public.document_groups
  for all to authenticated using (public.can_write()) with check (public.can_write());

-- Acesso dos grupos (sem login): valida a senha do grupo e devolve só o que foi publicado para ele.
create or replace function public.get_group_documents(p_slug text, p_password text)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  g public.groups;
begin
  select * into g from public.groups where slug = p_slug;
  if not found then
    return json_build_object('error', 'grupo não encontrado');
  end if;
  if g.password_hash is null or g.password_hash <> p_password then
    return json_build_object('error', 'senha incorreta');
  end if;
  return coalesce((
    select json_agg(json_build_object(
             'id', d.id, 'title', d.title, 'content', d.content, 'updated_at', d.updated_at)
           order by d.updated_at desc)
    from public.documents d
    where d.published
      and (d.shared_all or exists (
        select 1 from public.document_groups dg
        where dg.document_id = d.id and dg.group_id = g.id))
  ), '[]'::json);
end;
$$;

revoke all on function public.get_group_documents(text, text) from public;
grant execute on function public.get_group_documents(text, text) to anon, authenticated;

-- Imagens dos documentos: leitura pública, envio só para quem pode editar.
insert into storage.buckets (id, name, public)
values ('documentos', 'documentos', true)
on conflict (id) do nothing;

drop policy if exists documentos_public_read on storage.objects;
drop policy if exists documentos_write on storage.objects;
drop policy if exists documentos_update on storage.objects;
drop policy if exists documentos_delete on storage.objects;
create policy documentos_public_read on storage.objects
  for select to public using (bucket_id = 'documentos');
create policy documentos_write on storage.objects
  for insert to authenticated with check (bucket_id = 'documentos' and public.can_write());
create policy documentos_update on storage.objects
  for update to authenticated using (bucket_id = 'documentos' and public.can_write());
create policy documentos_delete on storage.objects
  for delete to authenticated using (bucket_id = 'documentos' and public.can_write());
