-- =====================================================================
-- Daily Report LKA - Tahap 5: hemat database
--   1. Semua data harian/transaksi yang lebih tua dari 1 tahun dihapus otomatis setiap hari 02.00 WIB
--      (penjualan, NOSELL, cek limit, laporan, kehadiran, MS Allbrand, riwayat stok, target,
--       riwayat login & perubahan, KPI bulan lama). Akun, toko, area, produk, dan stok terkini tetap.
--   2. MT dan Trainer bisa menghapus PERMANEN akun PC beserta semua datanya.
-- Jalankan SETELAH tahap_4.sql. Instalasi baru cukup schema.sql. Aman dijalankan ulang.
-- Jika muncul error tentang pg_cron: Database -> Extensions -> aktifkan pg_cron, lalu Run lagi.
-- =====================================================================

create or replace function public.stok_dari_penjualan() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  -- Pembersihan data lama / hapus permanen PC: stok toko tidak ikut berubah
  if coalesce(current_setting('lka.bersih', true), '') = '1' then return null; end if;
  if tg_op in ('UPDATE', 'DELETE') and old.potong_stok then
    perform public.ubah_stok(old.store_id, old.product_id, old.qty, public.today_wib(), 'batal_jual', old.id);
  end if;
  if tg_op in ('INSERT', 'UPDATE') and new.potong_stok then
    perform public.ubah_stok(new.store_id, new.product_id, -new.qty, public.today_wib(), 'jual', new.id);
  end if;
  return null;
end $$;

create or replace function public.audit_change() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  j jsonb := case when tg_op = 'DELETE' then to_jsonb(old) else to_jsonb(new) end;
  v_ref text;
begin
  if coalesce(current_setting('lka.bersih', true), '') = '1' then return null; end if;
  v_ref := case tg_table_name
    when 'products' then coalesce(j->>'area_id', '') || '|' || coalesce(j->>'kode', '')
    when 'store_targets' then (j->>'store_id') || '|' || (j->>'bulan') || '|' || (j->>'jenis')
    when 'pc_targets' then (j->>'pc_id') || '|' || (j->>'bulan') || '|' || (j->>'jenis')
    when 'insentif_produk' then (j->>'trainer_id') || '|' || (j->>'bulan') || '|' || (j->>'kode')
    when 'insentif_lain' then (j->>'trainer_id') || '|' || (j->>'bulan') || '|' || (j->>'kode')
    when 'kpi_gaji' then (j->>'trainer_id') || '|' || (j->>'bulan')
    else coalesce(j->>'id', '-') end;
  if tg_op = 'UPDATE' and to_jsonb(old) - 'diubah_pada' - 'updated_at' = to_jsonb(new) - 'diubah_pada' - 'updated_at' then
    return null;
  end if;
  insert into public.audit_log (tabel, ref, aksi, nilai_lama, nilai_baru, oleh)
  values (tg_table_name, v_ref, tg_op,
          case when tg_op <> 'INSERT' then to_jsonb(old) end,
          case when tg_op <> 'DELETE' then to_jsonb(new) end,
          public.my_profile_id());
  return null;
end $$;

-- -- 12b. HEMAT DATABASE: hapus otomatis data > 1 tahun & hapus permanen PC
-- ---------------------------------------------------------------------
create table if not exists public.bersih_log (
  id bigserial primary key,
  waktu timestamptz not null default now(),
  pemicu text,
  batas date,
  rincian jsonb
);
alter table public.bersih_log enable row level security;
drop policy if exists bersih_log_mt on public.bersih_log;
create policy bersih_log_mt on public.bersih_log for select to authenticated using (public.is_mt());

-- Hapus semua data harian/transaksi yang tanggalnya lebih tua dari 1 tahun (365 hari).
-- Master (akun, toko, area, produk, brand) dan stok terkini tidak dihapus.
-- Dijalankan otomatis setiap hari 02.00 WIB, atau oleh MT lewat menu Penyimpanan server.
create or replace function public.bersihkan_data_lama(p_pemicu text default 'jadwal') returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_batas date := public.today_wib() - 365;
  v_bulan date := date_trunc('month', public.today_wib() - 365)::date;
  r jsonb := '{}'::jsonb;
  n int;
begin
  perform set_config('lka.bersih', '1', true);
  delete from public.sales where tanggal < v_batas;                     get diagnostics n = row_count; r := r || jsonb_build_object('penjualan', n);
  delete from public.checkins where tanggal < v_batas;                  get diagnostics n = row_count; r := r || jsonb_build_object('nosell', n);
  delete from public.leasing_checks where tanggal < v_batas;            get diagnostics n = row_count; r := r || jsonb_build_object('cek_limit', n);
  delete from public.daily_reports where tanggal < v_batas;             get diagnostics n = row_count; r := r || jsonb_build_object('laporan', n);
  delete from public.pc_day_status where tanggal < v_batas;             get diagnostics n = row_count; r := r || jsonb_build_object('kehadiran', n);
  delete from public.competitor_sales_detail where tanggal < v_batas;   get diagnostics n = row_count; r := r || jsonb_build_object('ms_rincian', n);
  delete from public.competitor_sales where tanggal < v_batas;          get diagnostics n = row_count; r := r || jsonb_build_object('ms', n);
  delete from public.stok_mutasi where tanggal < v_batas;               get diagnostics n = row_count; r := r || jsonb_build_object('riwayat_stok', n);
  delete from public.stok_update where tanggal < v_batas;               get diagnostics n = row_count; r := r || jsonb_build_object('cek_stok', n);
  delete from public.store_targets where bulan < v_bulan;               get diagnostics n = row_count; r := r || jsonb_build_object('target_toko', n);
  delete from public.pc_targets where bulan < v_bulan;                  get diagnostics n = row_count; r := r || jsonb_build_object('target_pc', n);
  delete from public.login_log where waktu < now() - interval '365 days'; get diagnostics n = row_count; r := r || jsonb_build_object('riwayat_login', n);
  delete from public.audit_log where waktu < now() - interval '365 days'; get diagnostics n = row_count; r := r || jsonb_build_object('riwayat_perubahan', n);
  delete from public.bersih_log where waktu < now() - interval '365 days';
  -- KPI bulan lama: simpan bulan terakhir tiap Trainer yang masih jadi patokan
  delete from public.kpi_tier k where k.bulan < v_bulan and k.bulan < (select max(bulan) from public.kpi_gaji g where g.trainer_id = k.trainer_id);
  delete from public.kpi_potongan k where k.bulan < v_bulan and k.bulan < (select max(bulan) from public.kpi_gaji g where g.trainer_id = k.trainer_id);
  delete from public.kpi_aturan k where k.bulan < v_bulan and k.bulan < (select max(bulan) from public.kpi_gaji g where g.trainer_id = k.trainer_id);
  delete from public.insentif_produk k where k.bulan < v_bulan and k.bulan < (select max(bulan) from public.kpi_gaji g where g.trainer_id = k.trainer_id);
  delete from public.insentif_lain k where k.bulan < v_bulan and k.bulan < (select max(bulan) from public.kpi_gaji g where g.trainer_id = k.trainer_id);
  delete from public.kpi_gaji k where k.bulan < v_bulan and k.bulan < (select max(bulan) from public.kpi_gaji g where g.trainer_id = k.trainer_id);
  perform set_config('lka.bersih', '', true);
  insert into public.bersih_log (pemicu, batas, rincian) values (p_pemicu, v_batas, r);
  return r || jsonb_build_object('batas', v_batas);
end $$;

revoke execute on function public.bersihkan_data_lama(text) from public, anon, authenticated;

-- Tombol "Bersihkan sekarang" untuk MT
create or replace function public.bersihkan_sekarang() returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_mt() then raise exception 'Hanya Manajer Trainer'; end if;
  return public.bersihkan_data_lama('manual');
end $$;

-- Hapus PERMANEN akun PC beserta semua datanya (penjualan, cek limit, laporan, kehadiran, target, login).
-- Hanya MT (semua PC) dan Trainer (PC di wilayahnya). Stok toko tidak berubah.
create or replace function public.hapus_pc_permanen(p_pc uuid) returns jsonb
language plpgsql security definer set search_path = public, auth as $$
declare
  v public.profiles;
  n int;
begin
  select * into v from public.profiles where id = p_pc;
  if v.id is null or v.role <> 'pc' then raise exception 'Akun PC tidak ditemukan'; end if;
  if not (public.is_mt() or (public.my_role() = 'trainer' and public.can_manage_store(v.store_id))) then
    raise exception 'Hapus permanen hanya oleh Manajer Trainer atau Trainer wilayahnya';
  end if;
  perform set_config('lka.bersih', '1', true);
  delete from public.sales where pc_id = p_pc;
  get diagnostics n = row_count;
  delete from public.checkins where pc_id = p_pc;
  delete from public.leasing_checks where pc_id = p_pc;
  delete from public.daily_reports where pc_id = p_pc;
  delete from public.pc_day_status where pc_id = p_pc;
  delete from public.pc_targets where pc_id = p_pc;
  delete from public.login_log where profile_id = p_pc;
  update public.stok_mutasi set oleh = null where oleh = p_pc;
  update public.stok_update set oleh = null where oleh = p_pc;
  update public.competitor_sales set diinput_oleh = null where diinput_oleh = p_pc;
  update public.competitor_sales_detail set diinput_oleh = null where diinput_oleh = p_pc;
  update public.audit_log set oleh = null where oleh = p_pc;
  update public.sales set diinput_oleh = null where diinput_oleh = p_pc;
  update public.leasing_checks set diinput_oleh = null where diinput_oleh = p_pc;
  update public.checkins set oleh = null where oleh = p_pc;
  update public.daily_reports set dikirim_oleh = null where dikirim_oleh = p_pc;
  perform set_config('lka.bersih', '', true);
  if v.auth_uid is not null then delete from auth.users where id = v.auth_uid; end if;
  delete from public.profiles where id = p_pc;
  return jsonb_build_object('pc', v.nama, 'penjualan_dihapus', n);
end $$;

-- Info pembersihan untuk menu Penyimpanan server (MT)
create or replace function public.info_bersih() returns jsonb
language sql stable security definer set search_path = public as $$
  select case when not public.is_mt() then null else jsonb_build_object(
    'db_bytes', pg_database_size(current_database()),
    'batas', public.today_wib() - 365,
    'log', (select coalesce(jsonb_agg(to_jsonb(l) order by l.waktu desc), '[]'::jsonb)
              from (select * from public.bersih_log order by waktu desc limit 5) l)) end
$$;

-- Jadwal harian 02.00 WIB (= 19.00 UTC). Butuh ekstensi pg_cron (tersedia di Supabase).
create extension if not exists pg_cron;
do $$ begin
  perform cron.unschedule('lka-bersih-data-lama') where exists (select 1 from cron.job where jobname = 'lka-bersih-data-lama');
  perform cron.schedule('lka-bersih-data-lama', '0 19 * * *', $c$ select public.bersihkan_data_lama('jadwal'); $c$);
end $$;

select 'Tahap 5 siap' as status,
       (select count(*) from cron.job where jobname = 'lka-bersih-data-lama') as jadwal_harian;
