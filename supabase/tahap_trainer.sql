-- =====================================================================
-- Daily Report LKA - Tahap Trainer: peringkat Trainer + beranda versi Trainer
--   - Beranda MT: peringkat Trainer (unit, value, tipe fokus vs target)
--   - Peringkat Sales ikut menampilkan tipe fokus
--   - Semua kartu beranda bisa difilter per Trainer (p_trainer)
-- Jalankan SETELAH tahap_stok.sql. Instalasi baru cukup schema.sql. Aman dijalankan ulang.
-- =====================================================================

drop function if exists public.toko_filter(uuid, int, uuid);
drop function if exists public.pc_filter(uuid, int, uuid);
drop function if exists public.beranda(date, uuid, int, uuid);
drop function if exists public.kontribusi_tipe(date, uuid, int, uuid);
drop function if exists public.kontribusi_kategori(date, uuid, int, uuid);
drop function if exists public.kontribusi_bayar(date, date, uuid, int, uuid);
drop function if exists public.kalender_penjualan(date, uuid, int, uuid);

create or replace function public.toko_filter(p_sales uuid, p_store int, p_pc uuid, p_trainer uuid default null)
returns setof int
language sql stable security definer set search_path = public as $$
  select s.id from public.stores s join public.areas a on a.id = s.area_id
   where s.aktif and public.can_view_store(s.id)
     and (p_sales is null or a.sales_id = p_sales)
     and (p_store is null or s.id = p_store)
     and (p_pc is null or s.id = public.pc_store(p_pc))
     and (p_trainer is null or a.sales_id in (select ts.sales_id from public.trainer_sales ts where ts.trainer_id = p_trainer))
$$;

create or replace function public.pc_filter(p_sales uuid, p_store int, p_pc uuid, p_trainer uuid default null)
returns setof uuid
language sql stable security definer set search_path = public as $$
  select p.id from public.profiles p
   where p.role = 'pc' and p.aktif and p.store_id in (select public.toko_filter(p_sales, p_store, p_pc, p_trainer))
     and (p_pc is null or p.id = p_pc)
     and (public.my_role() <> 'pc' or p.id = public.my_profile_id())
$$;

create or replace function public.beranda(p_tanggal date, p_sales uuid default null, p_store int default null,
                                          p_pc uuid default null, p_trainer uuid default null) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_bulan date := date_trunc('month', p_tanggal)::date;
  r jsonb;
begin
  if not public.is_atasan() then raise exception 'Akses ditolak'; end if;
  with toko as (select public.toko_filter(p_sales, p_store, p_pc, p_trainer) as id),
  pc as (
    select p.id, p.nama, p.store_id, (select d.status from public.pc_day_status d where d.pc_id = p.id and d.tanggal = p_tanggal) as libur
      from public.profiles p where p.id in (select public.pc_filter(p_sales, p_store, p_pc, p_trainer))
  ),
  s as (
    select x.* from public.sales x
     where x.tanggal between v_bulan and p_tanggal and x.store_id in (select id from toko)
       and (p_pc is null or x.pc_id = p_pc)
  ),
  h as (select * from s where tanggal = p_tanggal),
  tgt_toko as (   -- target toko; jika kosong pakai jumlah target PC di toko itu
    select t.id as store_id, j.jenis,
           coalesce((select nullif(nilai, 0) from public.store_targets st where st.store_id = t.id and st.bulan = v_bulan and st.jenis = j.jenis),
                    (select sum(pt.nilai) from public.pc_targets pt join public.profiles pp on pp.id = pt.pc_id
                      where pp.store_id = t.id and pp.aktif and pt.bulan = v_bulan and pt.jenis = j.jenis), 0) as nilai
      from toko t cross join (values ('unit'), ('value'), ('fokus'), ('iot'), ('iot_value')) j(jenis)
  ),
  bertugas as (select * from pc where libur is null),
  tt_toko as (   -- toko per Trainer (lewat Sales area toko)
    select ts.trainer_id, st.id as store_id
      from public.stores st join public.areas a on a.id = st.area_id join public.trainer_sales ts on ts.sales_id = a.sales_id
     where st.id in (select id from toko)
  )
  select jsonb_build_object(
    'hari', jsonb_build_object(
      'unit', coalesce((select sum(qty) from h where tipe = 'HP'), 0),
      'value', coalesce((select sum(subtotal) from h where tipe = 'HP'), 0),
      'fokus', coalesce((select sum(qty) from h where fokus is not null), 0),
      'iot', coalesce((select sum(qty) from h where tipe = 'IOT'), 0),
      'iot_value', coalesce((select sum(subtotal) from h where tipe = 'IOT'), 0)),
    'bulan', jsonb_build_object(
      'unit', coalesce((select sum(qty) from s where tipe = 'HP'), 0),
      'value', coalesce((select sum(subtotal) from s where tipe = 'HP'), 0),
      'fokus', coalesce((select sum(qty) from s where fokus is not null), 0),
      'iot', coalesce((select sum(qty) from s where tipe = 'IOT'), 0),
      'iot_value', coalesce((select sum(subtotal) from s where tipe = 'IOT'), 0)),
    'target', case when p_pc is not null
                   then (select coalesce(jsonb_object_agg(jenis, nilai), '{}'::jsonb) from public.pc_targets
                          where pc_id = p_pc and bulan = v_bulan)
                   else (select coalesce(jsonb_object_agg(jenis, total), '{}'::jsonb)
                           from (select jenis, sum(nilai) as total from tgt_toko group by jenis) t) end,
    'produktivitas', jsonb_build_object(
      'pc_bertugas', (select count(*) from bertugas),
      'pc_menjual', (select count(distinct pc_id) from h where pc_id in (select id from bertugas)),
      'pc_total', (select count(*) from pc),
      'unit_bulan', coalesce((select sum(qty) from s where tipe = 'HP'), 0)),
    'laporan', jsonb_build_object(
      'wajib', (select count(*) from bertugas),
      'sudah', (select count(*) from public.daily_reports d where d.tanggal = p_tanggal and d.pc_id in (select id from bertugas)),
      'belum', (select coalesce(jsonb_agg(jsonb_build_object('pc_id', b.id, 'pc', b.nama, 'toko', st.nama) order by st.nama, b.nama), '[]'::jsonb)
                  from bertugas b join public.stores st on st.id = b.store_id
                 where not exists (select 1 from public.daily_reports d where d.pc_id = b.id and d.tanggal = p_tanggal))),
    'stok', jsonb_build_object(
      'total', (select count(*) from toko),
      'sudah', (select count(*) from public.stok_update sd where sd.tanggal = p_tanggal and sd.store_id in (select id from toko)),
      'toko', (select coalesce(jsonb_agg(jsonb_build_object(
                   'store_id', st.id, 'toko', st.nama, 'area', a.nama, 'area_id', st.area_id,
                   'update', (select sd.terakhir from public.stok_update sd where sd.store_id = st.id and sd.tanggal = p_tanggal),
                   'pc', (select coalesce(jsonb_agg(pp.nama order by pp.nama), '[]'::jsonb) from public.profiles pp
                           where pp.store_id = st.id and pp.role = 'pc' and pp.aktif))
                 order by a.nama, st.nama), '[]'::jsonb)
                 from public.stores st join public.areas a on a.id = st.area_id where st.id in (select id from toko))),
    'per_sales', (select coalesce(jsonb_agg(x order by (x->>'value')::numeric desc), '[]'::jsonb) from (
        select jsonb_build_object(
          'sales_id', a.sales_id,
          'sales', (select nama from public.profiles where id = a.sales_id),
          'area', string_agg(distinct a.nama, ', '),
          'trainer', (select p.nama from public.trainer_sales ts join public.profiles p on p.id = ts.trainer_id where ts.sales_id = a.sales_id),
          'unit', coalesce((select sum(qty) from s join public.stores st on st.id = s.store_id join public.areas aa on aa.id = st.area_id
                             where s.tipe = 'HP' and aa.sales_id is not distinct from a.sales_id), 0),
          'value', coalesce((select sum(subtotal) from s join public.stores st on st.id = s.store_id join public.areas aa on aa.id = st.area_id
                              where s.tipe = 'HP' and aa.sales_id is not distinct from a.sales_id), 0),
          'target_unit', coalesce((select sum(t.nilai) from tgt_toko t join public.stores st on st.id = t.store_id join public.areas aa on aa.id = st.area_id
                                    where t.jenis = 'unit' and aa.sales_id is not distinct from a.sales_id), 0),
          'target_value', coalesce((select sum(t.nilai) from tgt_toko t join public.stores st on st.id = t.store_id join public.areas aa on aa.id = st.area_id
                                     where t.jenis = 'value' and aa.sales_id is not distinct from a.sales_id), 0),
          'fokus', coalesce((select sum(qty) from s join public.stores st on st.id = s.store_id join public.areas aa on aa.id = st.area_id
                              where s.fokus is not null and aa.sales_id is not distinct from a.sales_id), 0),
          'target_fokus', coalesce((select sum(t.nilai) from tgt_toko t join public.stores st on st.id = t.store_id join public.areas aa on aa.id = st.area_id
                                     where t.jenis = 'fokus' and aa.sales_id is not distinct from a.sales_id), 0),
          'iot', coalesce((select sum(qty) from s join public.stores st on st.id = s.store_id join public.areas aa on aa.id = st.area_id
                            where s.tipe = 'IOT' and aa.sales_id is not distinct from a.sales_id), 0),
          'target_iot', coalesce((select sum(t.nilai) from tgt_toko t join public.stores st on st.id = t.store_id join public.areas aa on aa.id = st.area_id
                                   where t.jenis = 'iot' and aa.sales_id is not distinct from a.sales_id), 0),
          'toko', count(distinct st0.id),
          'pc', (select count(*) from pc join public.stores st on st.id = pc.store_id join public.areas aa on aa.id = st.area_id
                  where aa.sales_id is not distinct from a.sales_id)) as x
          from public.stores st0 join public.areas a on a.id = st0.area_id
         where st0.id in (select id from toko)
         group by a.sales_id) y),
    'per_trainer', (select coalesce(jsonb_agg(x order by (x->>'value')::numeric desc), '[]'::jsonb) from (
        select jsonb_build_object(
          'trainer_id', tt.trainer_id,
          'trainer', (select nama from public.profiles where id = tt.trainer_id),
          'sales', (select string_agg(p.nama, ', ' order by p.nama) from public.trainer_sales x join public.profiles p on p.id = x.sales_id
                     where x.trainer_id = tt.trainer_id),
          'unit', coalesce((select sum(qty) from s where s.tipe = 'HP' and s.store_id in (select store_id from tt_toko where trainer_id = tt.trainer_id)), 0),
          'value', coalesce((select sum(subtotal) from s where s.tipe = 'HP' and s.store_id in (select store_id from tt_toko where trainer_id = tt.trainer_id)), 0),
          'fokus', coalesce((select sum(qty) from s where s.fokus is not null and s.store_id in (select store_id from tt_toko where trainer_id = tt.trainer_id)), 0),
          'target_unit', coalesce((select sum(nilai) from tgt_toko t where t.jenis = 'unit' and t.store_id in (select store_id from tt_toko where trainer_id = tt.trainer_id)), 0),
          'target_value', coalesce((select sum(nilai) from tgt_toko t where t.jenis = 'value' and t.store_id in (select store_id from tt_toko where trainer_id = tt.trainer_id)), 0),
          'target_fokus', coalesce((select sum(nilai) from tgt_toko t where t.jenis = 'fokus' and t.store_id in (select store_id from tt_toko where trainer_id = tt.trainer_id)), 0),
          'iot', coalesce((select sum(qty) from s where s.tipe = 'IOT' and s.store_id in (select store_id from tt_toko where trainer_id = tt.trainer_id)), 0),
          'target_iot', coalesce((select sum(nilai) from tgt_toko t where t.jenis = 'iot' and t.store_id in (select store_id from tt_toko where trainer_id = tt.trainer_id)), 0),
          'toko', (select count(*) from tt_toko where trainer_id = tt.trainer_id),
          'pc', (select count(*) from pc where pc.store_id in (select store_id from tt_toko where trainer_id = tt.trainer_id))) as x
          from (select distinct trainer_id from tt_toko) tt) y),
    'per_pc', (select coalesce(jsonb_agg(x order by (x->>'value')::numeric desc, x->>'pc'), '[]'::jsonb) from (
        select jsonb_build_object(
          'pc_id', pc.id, 'pc', pc.nama, 'store_id', pc.store_id, 'toko', st.nama, 'libur', pc.libur,
          'unit', coalesce((select sum(qty) from s where s.pc_id = pc.id and tipe = 'HP'), 0),
          'value', coalesce((select sum(subtotal) from s where s.pc_id = pc.id and tipe = 'HP'), 0),
          'unit_hari', coalesce((select sum(qty) from h where h.pc_id = pc.id and tipe = 'HP'), 0),
          'iot', coalesce((select sum(qty) from s where s.pc_id = pc.id and tipe = 'IOT'), 0),
          'target_unit', (select nilai from public.pc_targets where pc_id = pc.id and bulan = v_bulan and jenis = 'unit'),
          'target_value', (select nilai from public.pc_targets where pc_id = pc.id and bulan = v_bulan and jenis = 'value'),
          'laporan_pada', (select dikirim_pada from public.daily_reports d where d.pc_id = pc.id and d.tanggal = p_tanggal),
          'last_seen', pp.last_seen, 'logged_in', pp.logged_in, 'sudah_daftar', pp.auth_uid is not null) as x
          from pc join public.stores st on st.id = pc.store_id join public.profiles pp on pp.id = pc.id) y)
  ) into r;
  return r;
end $$;

create or replace function public.kontribusi_tipe(p_tanggal date, p_sales uuid default null, p_store int default null,
                                                  p_pc uuid default null, p_trainer uuid default null) returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object(
           'tipe', tipe, 'grup', grup, 'nama', nama, 'unit', unit, 'value', value, 'unit_hari', unit_hari)
           order by tipe, urutan_grup, unit desc, nama), '[]'::jsonb)
    from (
      select x.tipe, coalesce(x.grup, '-') as grup, x.nama_produk as nama,
             sum(x.qty) as unit, sum(x.subtotal) as value,
             sum(x.qty) filter (where x.tanggal = p_tanggal) as unit_hari,
             case x.grup when 'A Series' then 1 when 'Reno Series' then 2 when 'Find Series' then 3 else 9 end as urutan_grup
        from public.sales x
       where x.tanggal between date_trunc('month', p_tanggal)::date and p_tanggal
         and x.store_id in (select public.toko_filter(p_sales, p_store, p_pc, p_trainer))
         and (p_pc is null or x.pc_id = p_pc)
         and public.can_view_pc(x.pc_id)
       group by 1, 2, 3, 7
    ) t
$$;

create or replace function public.kontribusi_kategori(p_tanggal date, p_sales uuid default null, p_store int default null,
                                                      p_pc uuid default null, p_trainer uuid default null) returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object('tipe', tipe, 'kategori', kategori, 'unit', unit, 'value', value,
                                               'unit_hari', unit_hari)), '[]'::jsonb)
    from (
      select x.tipe, coalesce(x.kategori_user, 'Belum diisi') as kategori,
             sum(x.qty) as unit, sum(x.subtotal) as value,
             coalesce(sum(x.qty) filter (where x.tanggal = p_tanggal), 0) as unit_hari
        from public.sales x
       where x.tanggal between date_trunc('month', p_tanggal)::date and p_tanggal
         and x.store_id in (select public.toko_filter(p_sales, p_store, p_pc, p_trainer))
         and (p_pc is null or x.pc_id = p_pc)
         and public.can_view_pc(x.pc_id)
       group by 1, 2
    ) t
$$;

create or replace function public.kontribusi_bayar(p_dari date, p_sampai date, p_sales uuid default null,
                                                   p_store int default null, p_pc uuid default null,
                                                   p_trainer uuid default null) returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object(
           'tipe', tipe, 'metode', metode, 'cara_bayar', cara_bayar, 'unit', unit, 'value', value)
         order by tipe, metode, value desc), '[]'::jsonb)
    from (
      select s.tipe, coalesce(s.metode, '-') as metode, coalesce(s.cara_bayar, '-') as cara_bayar,
             sum(s.qty) as unit, sum(s.subtotal) as value
        from public.sales s
       where s.tanggal between p_dari and p_sampai
         and s.store_id in (select public.toko_filter(p_sales, p_store, p_pc, p_trainer))
         and (p_pc is null or s.pc_id = p_pc)
         and public.can_view_pc(s.pc_id)
       group by 1, 2, 3
    ) x
$$;

create or replace function public.kalender_penjualan(p_bulan date, p_sales uuid default null, p_store int default null,
                                                     p_pc uuid default null, p_trainer uuid default null) returns jsonb
language sql stable security definer set search_path = public as $$
  with toko as (select public.toko_filter(p_sales, p_store, p_pc, p_trainer) as id),
  pcs as (select public.pc_filter(p_sales, p_store, p_pc, p_trainer) as id),
  hari as (
    select generate_series(date_trunc('month', p_bulan)::date,
                           (date_trunc('month', p_bulan) + interval '1 month - 1 day')::date,
                           interval '1 day')::date as tanggal
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'tanggal', h.tanggal,
           'unit', coalesce((select sum(qty) from public.sales s where s.tanggal = h.tanggal and s.tipe = 'HP'
                               and s.pc_id in (select id from pcs)), 0),
           'value', coalesce((select sum(subtotal) from public.sales s where s.tanggal = h.tanggal and s.tipe = 'HP'
                                and s.pc_id in (select id from pcs)), 0),
           'iot', coalesce((select sum(qty) from public.sales s where s.tanggal = h.tanggal and s.tipe = 'IOT'
                              and s.pc_id in (select id from pcs)), 0),
           'kompetitor', coalesce((select sum(unit) from public.competitor_sales c where c.tanggal = h.tanggal
                                     and c.store_id in (select id from toko)), 0),
           'lapor', (select count(*) from public.daily_reports d where d.tanggal = h.tanggal and d.pc_id in (select id from pcs)),
           'off', p_pc is not null and exists (select 1 from public.pc_day_status d where d.tanggal = h.tanggal and d.pc_id = p_pc),
           'nihil', p_pc is not null and exists (select 1 from public.checkins c where c.tanggal = h.tanggal
                                                    and c.modul = 'penjualan' and c.pc_id = p_pc)
         ) order by h.tanggal), '[]'::jsonb)
    from hari h
$$;

select 'Tahap Trainer siap' as status;
