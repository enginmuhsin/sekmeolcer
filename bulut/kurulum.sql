-- =====================================================================
-- SekmeÖlçer · Öğrenci kayıt defteri (Supabase kurulumu)
-- ---------------------------------------------------------------------
-- NASIL ÇALIŞTIRILIR
--   1. Aşağıda "declare s text := ..." satırındaki YONETICI_SIFRESI_BURAYA yazısını
--      kendi yönetici şifrenizle (en az 8 karakter) değiştirin. Tırnaklar kalsın.
--   2. Supabase panelinde: SQL Editor → New query → bu dosyanın tamamını yapıştırın → Run.
--   3. Tekrar çalıştırmak güvenlidir: tablolar ve kayıtlar silinmez, fonksiyonlar güncellenir.
--
-- GÜVENLİK MODELİ
--   * Tablolara dışarıdan doğrudan erişim YOK (RLS açık, hiçbir politika yok).
--   * Uygulama yalnızca aşağıdaki üç "kapı" fonksiyonunu çağırabilir:
--       sekme_giris, sekme_gonder, sekme_kayitlarim  (öğrenci kodu + PIN ister)
--       sekme_yonetici                               (yönetici şifresi ister)
--   * PIN ve şifreler bcrypt ile özetlenip saklanır; düz hâli hiçbir yerde durmaz.
--   * 8 hatalı denemeden sonra o kod (ya da yönetici girişi) 10 dakika kilitlenir.
--   * Öğrencinin gerçek adı, e-postası vb. HİÇBİR kişisel veri tutulmaz.
-- =====================================================================

create extension if not exists pgcrypto with schema extensions;

-- ---------- TABLOLAR ----------
create table if not exists public.sekme_ogrenci (
  kod          text primary key check (kod ~ '^[A-Z0-9-]{3,20}$'),
  pin_hash     text not null,
  aciklama     text not null default '',
  aktif        boolean not null default true,
  hatali       smallint not null default 0,
  kilit_bitis  timestamptz,
  son_giris    timestamptz,
  olusturma    timestamptz not null default now()
);

create table if not exists public.sekme_kayit (
  id           bigint generated always as identity primary key,
  ogrenci_kod  text not null references public.sekme_ogrenci(kod) on update cascade on delete cascade,
  istemci_id   text not null,
  tip          text not null default 'birakis' check (tip in ('birakis','video')),
  veri         jsonb not null,
  alindi       timestamptz not null default now(),
  unique (ogrenci_kod, istemci_id)
);
create index if not exists sekme_kayit_ogr_idx on public.sekme_kayit (ogrenci_kod, alindi);

create table if not exists public.sekme_ayar (
  anahtar      text primary key,
  deger        text not null,
  hatali       smallint not null default 0,
  kilit_bitis  timestamptz
);

alter table public.sekme_ogrenci enable row level security;
alter table public.sekme_kayit   enable row level security;
alter table public.sekme_ayar    enable row level security;
revoke all on public.sekme_ogrenci, public.sekme_kayit, public.sekme_ayar from anon, authenticated;

-- ---------- YÖNETİCİ ŞİFRESİ ----------
-- Yalnızca İLK kurulumda yazılır. Dosyayı sonra tekrar çalıştırmak şifreyi DEĞİŞTİRMEZ;
-- şifreyi yönetim panelindeki "Şifre değiştir" bölümünden değiştirin.
do $$
declare s text := 'YONETICI_SIFRESI_BURAYA';
begin
  if s = 'YONETICI' || '_SIFRESI_BURAYA' or length(s) < 8 then
    raise notice 'Yönetici şifresi yazılmadı: dosyadaki YONETICI_SIFRESI_BURAYA yerine en az 8 karakterli şifrenizi yazın.';
  else
    insert into public.sekme_ayar (anahtar, deger)
    values ('yonetici', extensions.crypt(s, extensions.gen_salt('bf')))
    on conflict (anahtar) do nothing;
  end if;
end $$;

-- ---------- YARDIMCILAR (dışarıya kapalı) ----------
create or replace function public._sekme_kod(p text) returns text
language sql immutable set search_path = public as $$
  select upper(translate(trim(coalesce(p, '')), 'çğıöşüÇĞİÖŞÜ', 'cgiosuCGIOSU'));
$$;

-- Öğrenci kodu + PIN doğrular. Dönüş: 'ok' | 'yok' | 'kilit' | 'pasif' | 'hatali'
create or replace function public._sekme_ogr_dogrula(p_kod text, p_pin text) returns text
language plpgsql security definer set search_path = public, extensions as $$
declare o public.sekme_ogrenci;
begin
  select * into o from public.sekme_ogrenci where kod = public._sekme_kod(p_kod) for update;
  if not found then return 'yok'; end if;
  if o.kilit_bitis is not null and o.kilit_bitis > now() then return 'kilit'; end if;
  if not o.aktif then return 'pasif'; end if;
  if o.pin_hash = extensions.crypt(coalesce(p_pin, ''), o.pin_hash) then
    update public.sekme_ogrenci set hatali = 0, kilit_bitis = null, son_giris = now() where kod = o.kod;
    return 'ok';
  end if;
  update public.sekme_ogrenci
     set hatali = case when o.hatali + 1 >= 8 then 0 else o.hatali + 1 end,
         kilit_bitis = case when o.hatali + 1 >= 8 then now() + interval '10 minutes' else null end
   where kod = o.kod;
  return 'hatali';
end $$;

create or replace function public._sekme_yon_dogrula(p_sifre text) returns text
language plpgsql security definer set search_path = public, extensions as $$
declare a public.sekme_ayar;
begin
  select * into a from public.sekme_ayar where anahtar = 'yonetici' for update;
  if not found then return 'yok'; end if;
  if a.kilit_bitis is not null and a.kilit_bitis > now() then return 'kilit'; end if;
  if a.deger = extensions.crypt(coalesce(p_sifre, ''), a.deger) then
    update public.sekme_ayar set hatali = 0, kilit_bitis = null where anahtar = 'yonetici';
    return 'ok';
  end if;
  update public.sekme_ayar
     set hatali = case when a.hatali + 1 >= 8 then 0 else a.hatali + 1 end,
         kilit_bitis = case when a.hatali + 1 >= 8 then now() + interval '10 minutes' else null end
   where anahtar = 'yonetici';
  return 'hatali';
end $$;

create or replace function public._sekme_hata(d text) returns jsonb
language sql immutable as $$
  select jsonb_build_object('ok', false, 'hata', d, 'mesaj', case d
    when 'yok'    then 'Bu öğrenci kodu bulunamadı.'
    when 'kilit'  then 'Çok fazla hatalı deneme. 10 dakika sonra tekrar deneyin.'
    when 'pasif'  then 'Bu kod öğretmen tarafından durduruldu.'
    when 'hatali' then 'Kod ya da PIN hatalı.'
    else d end);
$$;

-- ---------- ÖĞRENCİ KAPILARI ----------
create or replace function public.sekme_giris(p_kod text, p_pin text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare d text; k text := public._sekme_kod(p_kod);
begin
  d := public._sekme_ogr_dogrula(p_kod, p_pin);
  if d <> 'ok' then return public._sekme_hata(d); end if;
  return jsonb_build_object('ok', true, 'kod', k,
    'birakis', (select count(*) from public.sekme_kayit where ogrenci_kod = k and tip = 'birakis'),
    'video',   (select count(*) from public.sekme_kayit where ogrenci_kod = k and tip = 'video'));
end $$;

-- p_kayitlar: [{ "id": "...", "tip": "birakis"|"video", "veri": {...} }, ...]
create or replace function public.sekme_gonder(p_kod text, p_pin text, p_kayitlar jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare d text; k text := public._sekme_kod(p_kod); r jsonb; eklenen int := 0; n int; alinan jsonb := '[]'::jsonb;
begin
  d := public._sekme_ogr_dogrula(p_kod, p_pin);
  if d <> 'ok' then return public._sekme_hata(d); end if;
  if jsonb_typeof(p_kayitlar) <> 'array' then return public._sekme_hata('Kayıt listesi bozuk.'); end if;
  if jsonb_array_length(p_kayitlar) > 500 then return public._sekme_hata('Tek seferde en fazla 500 kayıt gönderilebilir.'); end if;
  for r in select * from jsonb_array_elements(p_kayitlar) loop
    if coalesce(r->>'id', '') = '' or length(r->>'id') > 200 or jsonb_typeof(r->'veri') <> 'object'
       or length((r->'veri')::text) > 8000 or coalesce(r->>'tip', 'birakis') not in ('birakis','video') then
      continue;
    end if;
    insert into public.sekme_kayit (ogrenci_kod, istemci_id, tip, veri)
    values (k, r->>'id', coalesce(r->>'tip', 'birakis'), r->'veri')
    on conflict (ogrenci_kod, istemci_id) do nothing;
    get diagnostics n = row_count; eklenen := eklenen + n;
    alinan := alinan || to_jsonb(r->>'id');
  end loop;
  return jsonb_build_object('ok', true, 'eklenen', eklenen, 'alinan', alinan);
end $$;

create or replace function public.sekme_kayitlarim(p_kod text, p_pin text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare d text; k text := public._sekme_kod(p_kod);
begin
  d := public._sekme_ogr_dogrula(p_kod, p_pin);
  if d <> 'ok' then return public._sekme_hata(d); end if;
  return jsonb_build_object('ok', true, 'kayitlar', coalesce((
    select jsonb_agg(jsonb_build_object('id', istemci_id, 'tip', tip, 'veri', veri, 'alindi', alindi) order by id)
      from public.sekme_kayit where ogrenci_kod = k), '[]'::jsonb));
end $$;

-- ---------- YÖNETİCİ KAPISI ----------
-- p_islem: ozet | kayitlar | ogrenci_ekle | pin_degistir | aktiflik | ogrenci_sil | kayit_sil | sifre_degistir
create or replace function public.sekme_yonetici(p_sifre text, p_islem text, p_veri jsonb default '{}'::jsonb)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare d text; k text; n int; v jsonb := coalesce(p_veri, '{}'::jsonb);
begin
  d := public._sekme_yon_dogrula(p_sifre);
  if d <> 'ok' then
    return public._sekme_hata(case d when 'hatali' then 'Yönetici şifresi hatalı.' when 'yok' then 'Yönetici şifresi kurulmamış.' else d end);
  end if;
  k := public._sekme_kod(v->>'kod');

  if p_islem = 'ozet' then
    return jsonb_build_object('ok', true, 'ogrenciler', coalesce((
      select jsonb_agg(jsonb_build_object(
        'kod', o.kod, 'aciklama', o.aciklama, 'aktif', o.aktif, 'son_giris', o.son_giris, 'olusturma', o.olusturma,
        'kilitli', (o.kilit_bitis is not null and o.kilit_bitis > now()),
        'birakis', (select count(*) from public.sekme_kayit x where x.ogrenci_kod = o.kod and x.tip = 'birakis'),
        'video',   (select count(*) from public.sekme_kayit x where x.ogrenci_kod = o.kod and x.tip = 'video'),
        'son_kayit', (select max(alindi) from public.sekme_kayit x where x.ogrenci_kod = o.kod)
      ) order by o.kod) from public.sekme_ogrenci o), '[]'::jsonb));

  elsif p_islem = 'kayitlar' then
    return jsonb_build_object('ok', true, 'kayitlar', coalesce((
      select jsonb_agg(jsonb_build_object('sid', id, 'kod', ogrenci_kod, 'id', istemci_id, 'tip', tip, 'veri', veri, 'alindi', alindi) order by ogrenci_kod, id)
        from public.sekme_kayit where k = '' or ogrenci_kod = k), '[]'::jsonb));

  elsif p_islem = 'ogrenci_ekle' then
    if k !~ '^[A-Z0-9-]{3,20}$' then return public._sekme_hata('Kod 3–20 karakter olmalı: harf, rakam ya da tire.'); end if;
    if coalesce(v->>'pin', '') !~ '^[0-9]{4,8}$' then return public._sekme_hata('PIN 4–8 haneli bir sayı olmalı.'); end if;
    if exists (select 1 from public.sekme_ogrenci where kod = k) then return public._sekme_hata('Bu kod zaten var.'); end if;
    insert into public.sekme_ogrenci (kod, pin_hash, aciklama)
    values (k, extensions.crypt(v->>'pin', extensions.gen_salt('bf')), left(coalesce(v->>'aciklama', ''), 80));
    return jsonb_build_object('ok', true, 'kod', k);

  elsif p_islem = 'pin_degistir' then
    if coalesce(v->>'pin', '') !~ '^[0-9]{4,8}$' then return public._sekme_hata('PIN 4–8 haneli bir sayı olmalı.'); end if;
    update public.sekme_ogrenci set pin_hash = extensions.crypt(v->>'pin', extensions.gen_salt('bf')), hatali = 0, kilit_bitis = null where kod = k;
    get diagnostics n = row_count;
    return case when n = 1 then jsonb_build_object('ok', true) else public._sekme_hata('Öğrenci bulunamadı.') end;

  elsif p_islem = 'aktiflik' then
    update public.sekme_ogrenci set aktif = coalesce((v->>'aktif')::boolean, true), hatali = 0, kilit_bitis = null where kod = k;
    get diagnostics n = row_count;
    return case when n = 1 then jsonb_build_object('ok', true) else public._sekme_hata('Öğrenci bulunamadı.') end;

  elsif p_islem = 'ogrenci_sil' then
    delete from public.sekme_ogrenci where kod = k;
    get diagnostics n = row_count;
    return case when n = 1 then jsonb_build_object('ok', true) else public._sekme_hata('Öğrenci bulunamadı.') end;

  elsif p_islem = 'kayit_sil' then
    delete from public.sekme_kayit where id = (v->>'sid')::bigint;
    get diagnostics n = row_count;
    return jsonb_build_object('ok', true, 'silinen', n);

  elsif p_islem = 'sifre_degistir' then
    if length(coalesce(v->>'yeni', '')) < 8 then return public._sekme_hata('Yeni şifre en az 8 karakter olmalı.'); end if;
    update public.sekme_ayar set deger = extensions.crypt(v->>'yeni', extensions.gen_salt('bf')) where anahtar = 'yonetici';
    return jsonb_build_object('ok', true);
  end if;

  return public._sekme_hata('Bilinmeyen işlem.');
end $$;

-- ---------- YETKİLER ----------
revoke all on function public._sekme_kod(text), public._sekme_ogr_dogrula(text, text),
  public._sekme_yon_dogrula(text), public._sekme_hata(text) from public, anon, authenticated;
revoke all on function public.sekme_giris(text, text), public.sekme_gonder(text, text, jsonb),
  public.sekme_kayitlarim(text, text), public.sekme_yonetici(text, text, jsonb) from public;
grant execute on function public.sekme_giris(text, text), public.sekme_gonder(text, text, jsonb),
  public.sekme_kayitlarim(text, text), public.sekme_yonetici(text, text, jsonb) to anon, authenticated;
