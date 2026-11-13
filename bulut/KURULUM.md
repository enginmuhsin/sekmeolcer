# SekmeÖlçer · Öğrenci defteri kurulumu

Öğrenciler kod + PIN ile girer, kaydettikleri bırakışlar hem telefonda kalır hem de buluttaki defterlerine gider.
Öğretmen `yonetim.html` sayfasından yönetici şifresiyle bütün defterleri görür.
Hiçbir kişisel veri (ad, e-posta, telefon) tutulmaz.

## Mevcut durum (13 Kasım 2026)

Kurulum **masterclassgeo** Supabase projesine yapıldı (sitenin diğer tablolarıyla aynı veritabanı;
tablolar `sekme_` önekiyle ayrı duruyor, başka hiçbir tabloya dokunulmadı). `bulut-ayar.js` dolduruldu.
Aşağıdaki adımlar, sıfırdan başka bir projeye kurmak gerekirse diye duruyor.

## Bir kerelik kurulum (telefondan yapılabilir)

1. **Supabase projesi aç.** supabase.com → giriş → *New project*.
   Ad: `sekmeolcer`, bölge: *Central EU (Frankfurt)*. Veritabanı şifresini bir yere not edin (bu, yönetici şifresi değil).
2. **Tabloları kur.** Sol menü → *SQL Editor* → *New query*.
   `bulut/kurulum.sql` dosyasının tamamını yapıştırın.
   `declare s text := 'YONETICI_SIFRESI_BURAYA';` satırında tırnak içini kendi yönetici şifrenizle değiştirin (en az 8 karakter) → *Run*.
   ⚠️ Şifreyi yalnızca Supabase editöründe yazın; GitHub'daki dosyaya yazmayın (site herkese açık).
3. **Bağlantı bilgilerini alın.** *Project Settings → API Keys* (ya da üstteki *Connect*):
   - Project URL (ör. `https://abcd1234.supabase.co`)
   - *Publishable key* (`sb_publishable_…`) ya da eski adıyla *anon public* anahtar.
   Bu ikisi gizli değildir; `bulut-ayar.js` dosyasına yazılır. (*secret / service_role* anahtarını ASLA paylaşmayın.)
4. **`bulut-ayar.js`'yi doldurun** ve siteyi yayına alın. Doldurulana kadar uygulama eskisi gibi çalışır, defter bölümü görünmez.
5. **Öğrencileri ekleyin:** `https://sekmeolcer.muhsinengin.com/yonetim.html` → yönetici şifresi → *Öğrenci ekle*.
   Her öğrenciye kod + PIN verin. PIN sonradan görülemez; unutulursa *Yeni PIN* ile yenisi verilir.

## Nasıl çalışır?

- Öğrenci uygulamanın en üstündeki **Öğrenci defteri** kutusundan girer. Telefon kodu ve PIN'i hatırlar.
- "Geçerli bırakışları kaydet"e basınca kayıt önce telefona yazılır, sonra deftere gönderilir.
- İnternet yoksa kayıtlar kuyrukta bekler; bağlantı gelince, sayfa yeniden açılınca ya da dakikada bir kendiliğinden gönderilir.
- Aynı kayıt iki kez gönderilse bile defterde bir kez durur.
- Öğrenci başka bir telefona geçerse *Defterimdeki kayıtları bu telefona getir* ile kayıtlarını geri alır.
- Girişten önce telefonda yapılmış ölçümler, öğrenci isterse tek düğmeyle deftere eklenir.
- Defterdeki kayıtları yalnızca öğretmen silebilir. Telefondaki silme, buluttakini etkilemez.

## Güvenlik özeti

- Tablolara dışarıdan doğrudan erişim kapalı (RLS). Uygulama yalnızca dört fonksiyonu çağırabilir:
  `sekme_giris`, `sekme_gonder`, `sekme_kayitlarim` (kod + PIN), `sekme_yonetici` (yönetici şifresi).
- PIN ve şifreler bcrypt ile özetlenip saklanır.
- 8 hatalı denemeden sonra o öğrenci kodu (ya da yönetici girişi) 10 dakika kilitlenir.
- `kurulum.sql` tekrar çalıştırılabilir: kayıtlar silinmez, yönetici şifresi değişmez.
  Şifre değiştirmek için panelin en altındaki bölümü kullanın.
