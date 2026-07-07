# AquaOps Botu

n8n öğrenme projesi — hobi/deneme ama **canlı Aquatronic ERP verisiyle** çalışan gerçek bir
otomasyon. Amaç: CV'ye "uçtan uca çalışan gerçek bir n8n deneyimi" yazabilmek.

## Ne yapıyor

İki n8n akışı + bir "bekçi" (error workflow), canlı Supabase ERP'sine salt-okunur bağlanıyor:

- **Akış A — ERP Gözcüsü:** her sabah 08:45 kritik stok + açık üretim emirleri + son 24 saat
  stok hareketini toplar, Gemini ile Türkçe özet çıkarır, mail (Gmail SMTP) + Telegram olarak
  gönderir. Kritik stok varsa ayrı bir "Acil Uyarı" Telegram mesajı da paralel dalda gider.
- **Akış B — Telegram ERP Asistanı:** Salih Telegram'dan yazınca (stok/emir/kur/sohbet) niyeti
  Gemini ile sınıflandırıp sabit, parametreli Postgres sorgularıyla cevap üretir. LLM asla SQL
  üretmez.
- **Bekçi (Error Workflow):** Akış A veya B hata verirse Salih'e ⛔ Telegram uyarısı yollar.
  **Çalışması için AKTİF olması ŞART** — bkz. "Öğrenilen dersler" altında.

## Mimari

```
D:\n8n-ops-bot\
├── start_n8n.cmd          # tünel + n8n'i başlatan reçete (aşağıda)
├── .secrets.env           # kurulum sırrı ara belleği — gitignore, git'e girmez
├── .n8n\                  # n8n verisi: SQLite DB + şifreli credential store — gitignore
├── workflows\             # sır içermeyen temiz JSON exportlar — git'e girer
├── db\                    # n8n_ro rolü DDL + rollback
├── tools\run_sql.js       # DDL'i koşan yardımcı script
└── docs\superpowers\      # spec + implementation plan (as-built notlarıyla güncel)
```

```
Telegram Trigger (webhook, tünel üzerinden)  Schedule Trigger (08:45)
        ↓                                            ↓
  IF: chat_id == Salih                        3× Postgres sorgu → paketle
        ↓ (guard geçerse)                            ↓
  Gemini: niyet sınıflandır (JSON)          ┌─────────┴─────────┐
        ↓                                Gemini özet         IF: kritik var mı?
  Switch: stok / emir / kur / sohbet          ↓                   ↓ (varsa)
        ↓                              Mail + Telegram      Acil Uyarı (Telegram)
  Telegram sendMessage (cevap)          (günlük rapor)

              Herhangi bir akış hata verirse → Bekçi (Error Workflow) → ⛔ Telegram
```

## Kurulum

```powershell
$env:N8N_USER_FOLDER = 'D:\n8n-ops-bot'
npm install --legacy-peer-deps   # ŞART: düz `npm i` zod/@langchain peer-dep çakışmasıyla n8n'i çökertiyor
```

### Başlatma reçetesi (kanıtlı)

n8n 2.29'da yerleşik `n8n start --tunnel` **kaldırıldı** (sessizce yok sayılıyor, hata vermiyor).
Yerine manuel tünel + `WEBHOOK_URL` env kombosu kullanılıyor:

```bash
# 1) Tüneli başlat, arkaplanda tut
cd D:/n8n-ops-bot && npx --yes localtunnel --port 5678
# çıktıdaki https://XXX.loca.lt adresini al

# 2) n8n'i o adresle başlat
N8N_USER_FOLDER='D:\n8n-ops-bot' \
GENERIC_TIMEZONE='Europe/Istanbul' \
WEBHOOK_URL='https://XXX.loca.lt/' \
"D:/n8n-ops-bot/node_modules/.bin/n8n.cmd" start
```

Boot 30 saniye–4 dakika arası sürebilir ("Database is not ready!" / healthz 503 bu sürede
normal). Hazır olduğunda `http://localhost:5678/healthz` → `{"status":"ok"}`.

⚠️ **loca.lt free-tier kırılgan:** tünel prosesi ara sıra kendiliğinden ölüyor ve her yeniden
doğuşta URL değişiyor → n8n'i yeni `WEBHOOK_URL` ile yeniden başlatmak gerekiyor. Kalıcı çözüm:
ngrok veya cloudflared ile sabit alan adı.

## Sırların yeri

Hiçbir sır git'e veya workflow JSON'larına girmiyor:

- **Nihai depo:** n8n'in kendi şifreli credential store'u (`.n8n\database.sqlite`, n8n'in
  şifreleme anahtarıyla şifreli) — Telegram bot token, Gemini API anahtarı, Gmail uygulama
  şifresi, Postgres (`n8n_ro`) şifresi buradan credential id'leriyle (`AqTelegramBot001`,
  `AqGeminiHeader001`, `AqGmailSmtp00001`, `AqErpPostgres001`) referans alınıyor.
- **Kurulum sırası ara bellek:** `.secrets.env` (gitignore) — yalnız ilk kurulumda credential
  import etmek için kullanıldı, sonrasında referans amaçlı duruyor.

## `n8n_ro` salt-okunur DB rolü

ERP'ye (Supabase Postgres, canlı prod) yalnızca `SELECT` yetkisiyle bağlanmak için ayrı bir rol
açıldı: `db/setup_n8n_ro.sql` (rol + gerekli tablolara `GRANT SELECT` + RLS policy + salt-okunur
transaction ayarı). Geri almak gerekirse `db/rollback_n8n_ro.sql` aynı yetkileri söküyor —
DDL'ler `tools/run_sql.js` ile koşuluyor (`node tools/run_sql.js <baglanti-stringi> <sql-dosyasi>`).
Kanıt: `n8n_ro` ile okuma 542 kalem döndü, `INSERT` denemesi reddedildi.

## Canlı test kanıtları

- **2026-07-07:** Akış A CLI ile uçtan uca çalıştırıldı — gerçek mail + Telegram raporu gitti
  (kritik stok listesi ERP'den geldi, çok sayıda 0-stok kalem tespit edildi).
- **2026-07-07:** Akış B canlı testleri, Salih telefondan yazıp cevap aldı:
  - "412 stok?" → 📦 AquaLIGHT 412: 153 / 412C: 298
  - "emirler" → "Acik uretim emri yok"
  - "kur" → 💱 EUR/TRY 53.42, USD/TRY 46.80
  - "selam napiyorsun" → sohbet cevabı — **ilk denemede Türkçe karakterler bozuk çıktı**
    (bkz. aşağıdaki ders), fix sonrası doğrulandı: "...Aquatronic'in **küçük yardımcısı**
    AquaOps. **İyiyim**, ... sana **yardımcı** olmaya **hazırım**..." — tamamı doğru UTF-8.
- **2026-07-07:** Guard testi — sahte `chat_id=999` ile webhook'a POST atıldı; akış yalnız
  `Telegram Dinle` → `Salih Mi` (IF) node'larında durdu, downstream hiçbir node çalışmadı,
  Telegram'a cevap gitmedi. Guard doğrulandı.
- **2026-07-07:** Bekçi chaos testi — kasıtlı hata üreten bir mini test workflow'u (webhook
  tetikli, `throw new Error(...)`) çalıştırıldı. **İlk denemede Bekçi mesaj GÖNDERMEDİ** çünkü
  Bekçi workflow'u pasifti (bkz. aşağıdaki ders); aktifleştirilip tekrar tetiklenince ⛔ mesajı
  doğru şekilde gitti: workflow adı + hata mesajı + execution id. Test workflow'u sonra silindi.

## ⚠️ n8n'in 08:45'te açık olması gerekir

Akış A'nın Schedule Trigger'ı tetiklenmek için n8n prosesinin **o an çalışıyor olması** lazım —
bilgisayar kapalıysa veya n8n kapalıysa sabah raporu gitmez (kaçırılan tetikler geriye dönük
çalışmaz). Kalıcılaştırma seçeneği (Salih isterse): Windows **Görev Zamanlayıcı**'da "oturum
açılışında" tetiklenen bir görev tanımlanıp `start_n8n.cmd`'yi (tünel dahil) otomatik başlatacak
şekilde ayarlanabilir. Şu an bu OTOMATİK KURULMADI — manuel başlatma reçetesiyle çalışıyor.

## Öğrenilen n8n kavramları (CV cümlesi hammaddesi)

- **Trigger tipleri:** Schedule Trigger, Telegram Trigger (webhook tabanlı, `secret_token`
  doğrulamalı), Manual Trigger, Webhook node, Error Trigger.
- **Akış kontrolü:** IF (guard + paralel karar dalı), Switch (çoklu niyet yönlendirme), Merge
  değil ama çoklu-çıkış fan-out (bir node'un iki farklı node'a paralel bağlanması).
- **Entegrasyon node'ları:** HTTP Request (LLM'i native node yerine REST ile çağırma —
  `responseFormat` ayarının UTF-8 kodlamasını nasıl bozabildiği dahil), Postgres (parametreli
  sorgu, salt-okunur rol), Telegram (trigger + sendMessage, `parse_mode`/`appendAttribution`
  tuzakları), Email Send (SMTP + uygulama şifresi).
- **Code node:** JS ile veri paketleme/parse (`JSON.parse`, HTML escape, karakter limiti kırpma).
- **Credential store:** şifreli, id-referanslı, workflow JSON'larından ayrı; `import:credentials`
  CLI'ı ile toplu yükleme.
- **Error Workflow mekanizması:** `settings.errorWorkflow` referansı + **hedef workflow'un aktif
  olması zorunluluğu** (pasifken sessizce çalışmıyor, yalnız log'da görünüyor).
- **Execution modes:** `manual` (Test Workflow butonu — Error Workflow'u TETİKLEMEZ),
  `webhook`, `cli`, `error`, `internal` — her birinin farklı hook davranışı var.
- **REST API ile programatik yönetim:** login/cookie, workflow CRUD, activate/deactivate
  (`versionId` zorunlu), archive→delete sırası, execution sorgulama (`includeData=true`,
  **Flatted** serileştirme formatı — döngüsel referanslı execution verisini JSON'a sığdırmak
  için kullanılan bir format, `flatted` npm paketiyle çözülüyor).
- **Windows native n8n işletimi:** `--legacy-peer-deps` gerekliliği, `N8N_USER_FOLDER` zorunluluğu,
  tünelin harici bir araca (`localtunnel`/ngrok/cloudflared) taşınması (2.29'da yerleşik tünel
  kaldırıldı).

## Faz-2 fikirleri (yapılmadı, ileride denenebilir)

- **AI Agent node** — mevcut "Switch ile sabit dallar" yerine LLM'e tool-calling ile Postgres
  sorgusu seçtirme (dikkatli: LLM'in SQL üretmemesi ilkesini bozmadan, yalnız *hangi* sabit
  aracı çağıracağına karar vermesi şeklinde sınırlı tutulmalı).
- **Merge node** — Akış A'daki üç ardışık Postgres sorgusunu paralel çalıştırıp Merge ile
  birleştirerek biraz hızlandırma egzersizi (şu an sıralı).
- **Native Gemini node'una geçiş** — şu an HTTP Request + manuel JSON parse ile çalışıyor;
  n8n'in resmi Google Gemini node'u varsa ona geçip credential/response handling'in nasıl
  sadeleştiğini karşılaştırma egzersizi.
- **Kalıcı tünel** — ngrok/cloudflared sabit alan adına geçiş, `start_n8n.cmd`'yi Görev
  Zamanlayıcı'ya bağlama.
