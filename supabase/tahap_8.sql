-- =====================================================================
-- TAHAP 8: Stok kompetitor (total per brand per toko) + Rekap stok & DOS per toko.
-- Aman dijalankan berulang kali.
-- =====================================================================

create table if not exists public.stok_kompetitor (
  store_id int not null references public.stores(id),
  brand text not null check (brand in ('VIVO','SAMSUNG','REALME','INFINIX','XIAOMI','TECNO','ITEL','OTHERS')),
  unit int not null default 0 check (unit >= 0),
  diinput_oleh uuid references public.profiles(id),
  updated_at timestamptz not null default now(),
  primary key (store_id, brand)
);
alter table public.stok_kompetitor enable row level security;
drop policy if exists stok_kompetitor_read on public.stok_kompetitor;
create policy stok_kompetitor_read on public.stok_kompetitor for select to authenticated
  using (public.can_view_store(store_id));
grant select on public.stok_kompetitor to authenticated;

-- Simpan stok kompetitor toko: p_data = {"VIVO": 12, "SAMSUNG": 8, ...}
create or replace function public.simpan_stok_kompetitor(p_store int, p_data jsonb) returns void
language plpgsql security definer set search_path = public as $$
declare b text;
begin
  if not coalesce((public.my_role() = 'pc' and p_store = public.my_store_id()) or public.can_manage_store(p_store), false) then
    raise exception 'Tidak diizinkan mengubah stok kompetitor toko ini.';
  end if;
  foreach b in array array['VIVO','SAMSUNG','REALME','INFINIX','XIAOMI','TECNO','ITEL','OTHERS'] loop
    insert into public.stok_kompetitor (store_id, brand, unit, diinput_oleh, updated_at)
    values (p_store, b, greatest(coalesce((p_data->>b)::int, 0), 0), public.my_profile_id(), now())
    on conflict (store_id, brand) do update
      set unit = excluded.unit, diinput_oleh = excluded.diinput_oleh, updated_at = now();
  end loop;
end $$;
grant execute on function public.simpan_stok_kompetitor(int, jsonb) to authenticated;

-- Rekap stok terkini (MT & Manajer: semua area; Trainer & Sales: area cakupannya) per area Sales, per toko & per series
-- + penjualan bulan berjalan (untuk DOS di aplikasi) + stok kompetitor per toko.
-- DOS (days of stock) = stok / rata-rata jual per hari (unit tgl 1 s.d. p_tanggal / jumlah hari).
create or replace function public.rekap_stok(p_tanggal date) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_awal date := date_trunc('month', p_tanggal)::date;
  r jsonb;
begin
  if not public.is_atasan() then raise exception 'Akses ditolak'; end if;
  with x as (
    select st.area_id, st.id as store_id, p.tipe, case when p.tipe = 'IOT' then 'IoT' else p.grup end as grup, s.qty as stok, 0 as jual
      from public.stok s join public.products p on p.id = s.product_id join public.stores st on st.id = s.store_id
     where st.aktif and st.area_id in (select public.area_cakupan())
    union all
    select st.area_id, st.id, j.tipe, case when j.tipe = 'IOT' then 'IoT' else coalesce(j.grup, '-') end, 0, j.qty
      from public.sales j join public.stores st on st.id = j.store_id
     where j.tanggal between v_awal and p_tanggal and st.aktif and st.area_id in (select public.area_cakupan())
  ),
  g as (select area_id, store_id, tipe, grup, sum(stok) as stok, sum(jual) as jual from x group by 1, 2, 3, 4)
  select jsonb_build_object(
    'dari', v_awal, 'sampai', p_tanggal, 'hari', p_tanggal - v_awal + 1,
    'area', (select coalesce(jsonb_agg(jsonb_build_object(
        'area_id', a.id, 'area', a.nama,
        'sales', (select nama from public.profiles where id = a.sales_id),
        'toko', (select count(*) from public.stores where area_id = a.id and aktif),
        'toko_stok_awal', (select count(*) from public.stores where area_id = a.id and aktif and stok_awal_pada is not null),
        'rows', (select coalesce(jsonb_agg(jsonb_build_object('tipe', q.tipe, 'grup', q.grup, 'stok', q.stok, 'jual', q.jual)), '[]'::jsonb)
                   from (select tipe, grup, sum(stok) as stok, sum(jual) as jual from g where g.area_id = a.id group by 1, 2) q),
        'toko_list', (select coalesce(jsonb_agg(jsonb_build_object(
              'store_id', s.id, 'toko', s.nama,
              'pc', (select string_agg(p.nama, ', ' order by p.nama) from public.profiles p where p.role = 'pc' and p.store_id = s.id and coalesce(p.aktif, true)),
              'stok_awal', s.stok_awal_pada is not null,
              'rows', (select coalesce(jsonb_agg(jsonb_build_object('tipe', g.tipe, 'grup', g.grup, 'stok', g.stok, 'jual', g.jual)), '[]'::jsonb)
                         from g where g.store_id = s.id),
              'kompetitor', (select coalesce(jsonb_object_agg(k.brand, k.unit), '{}'::jsonb) from public.stok_kompetitor k where k.store_id = s.id),
              'kompetitor_pada', (select max(k.updated_at) from public.stok_kompetitor k where k.store_id = s.id))
            order by s.nama), '[]'::jsonb)
            from public.stores s where s.area_id = a.id and s.aktif))
      order by a.nama), '[]'::jsonb) from public.areas a where a.id in (select public.area_cakupan()))
  ) into r;
  return r;
end $$;

select 'ok' as tahap_8,
       (select count(*) from pg_proc where proname in ('simpan_stok_kompetitor', 'rekap_stok')) as fungsi_harus_2;
