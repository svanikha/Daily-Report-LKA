-- =====================================================================
-- Daily Report LKA - Data awal: Trainer, Sales, area, toko, PC
-- Jalankan SETELAH schema.sql. Aman dijalankan ulang (yang sudah ada tidak digandakan).
-- Data berikutnya cukup ditambah lewat aplikasi (menu Kelola), tidak perlu file ini lagi.
--
-- Email hanya kunci di belakang layar; pengguna cukup memilih nama di layar login lalu
-- membuat password sendiri saat login pertama.
--
-- Cara mengisi: ganti baris CONTOH di setiap blok "values" di bawah, lalu hapus tanda "--"
-- di depan blok insert. (Akan diisi dari daftar yang dikirim.)
-- =====================================================================

-- 1. TRAINER: (nama, email)
-- insert into public.profiles (nama, role, email)
-- select v.nama, 'trainer', v.email from (values
--   ('Nama Trainer A', 'trainer.a@dailyreportlka.app')
-- ) v(nama, email)
-- on conflict (email) do update set nama = excluded.nama, role = 'trainer', aktif = true;

-- 2. SALES: (nama, email, email trainer yang memegang)
-- insert into public.profiles (nama, role, email)
-- select v.nama, 'sales', v.email from (values
--   ('Heri Supratman', 'heri@dailyreportlka.app', 'trainer.a@dailyreportlka.app')
-- ) v(nama, email, trainer)
-- on conflict (email) do update set nama = excluded.nama, role = 'sales', aktif = true;
--
-- insert into public.trainer_sales (sales_id, trainer_id)
-- select s.id, t.id from (values
--   ('heri@dailyreportlka.app', 'trainer.a@dailyreportlka.app')
-- ) v(sales, trainer)
-- join public.profiles s on s.email = v.sales
-- join public.profiles t on t.email = v.trainer
-- on conflict (sales_id) do update set trainer_id = excluded.trainer_id;

-- 3. AREA: (nama area, email Sales pemilik). Area baru otomatis mendapat list produk awal.
-- insert into public.areas (nama, sales_id)
-- select v.nama, s.id from (values
--   ('PKY 1', 'heri@dailyreportlka.app')
-- ) v(nama, sales)
-- join public.profiles s on s.email = v.sales
-- on conflict (nama) do update set sales_id = excluded.sales_id;

-- 4. TOKO: (nama toko, nama area)
-- insert into public.stores (nama, area_id)
-- select v.nama, a.id from (values
--   ('Toko Contoh Jaya', 'PKY 1')
-- ) v(nama, area)
-- join public.areas a on a.nama = v.area
-- on conflict (area_id, nama) do nothing;

-- 5. PC: (nama, email, nama toko, nama area). Satu toko boleh lebih dari satu PC.
-- insert into public.profiles (nama, role, store_id, email)
-- select v.nama, 'pc', s.id, v.email from (values
--   ('Nama PC', 'pc.nama@dailyreportlka.app', 'Toko Contoh Jaya', 'PKY 1')
-- ) v(nama, email, toko, area)
-- join public.areas a on a.nama = v.area
-- join public.stores s on s.nama = v.toko and s.area_id = a.id
-- on conflict (email) do update set nama = excluded.nama, store_id = excluded.store_id, aktif = true;

-- Hubungkan akun login yang mungkin sudah dibuat sebelumnya
update public.profiles p set auth_uid = u.id
  from auth.users u
 where lower(u.email) = lower(p.email) and p.auth_uid is null;

select (select count(*) from public.profiles where role = 'trainer') as trainer,
       (select count(*) from public.profiles where role = 'sales') as sales,
       (select count(*) from public.areas) as area,
       (select count(*) from public.stores) as toko,
       (select count(*) from public.profiles where role = 'pc') as pc,
       (select count(*) from public.products) as produk_semua_area;
