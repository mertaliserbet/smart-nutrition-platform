# 12 — Ekip görevleri, Codex koordinasyonu, yol haritası ve kararlar

**Repo:** `smart-nutrition-platform` · **Başlangıç:** 15.10.2026 · **Doküman sürümü:** `DOCS-V1` · **Durum:** onay bekleyen teknik öneriler mevcut.

## Görev dağılımı — sabit niyet
| Geliştirici | Ana sorumluluk | Sahiplik sınırı |
|---|---|---|
| **Mert Ali** | Danışan **mobil uygulaması**, kamera/görsel işleme entegrasyonu, mobil özelliklerin API ihtiyaçları | Mobil ekran/servis ve ilgili danışan endpointleri üzerinde çalışır |
| **Uğur Çetin** | **Web uygulaması**, diyetisyen/admin paneli, web iş akışlarının backend uygulamaları | Web ekran/servis ve diyetisyen/plan/admin endpointleri üzerinde çalışır |
| **Ortak** | Gıda görüntü analizi, kalori/porsiyon modeli, kan/vitamin-laboratuvar AI/ML, ortak sözleşmeler, entegrasyon ve güvenlik | Her ortak modül için tek PR lideri atanır; paralel çakışan kod yazılmaz |

**Başlangıç önerisi, onay bekliyor:** `auth`/JWT/rol ve ilişki temelinin backend lideri Uğur olsun; Mert mobil auth UI/entegrasyonunu yapsın. `meal-logs`, `water-logs`, `activity-logs` backend lideri Mert olsun. `dietitian-relationships` ve `nutrition-plans` backend lideri Uğur olsun. Ortak AI endpointlerinin lideri her sprintte belirlenir. İkisi aynı C# dosyalarını paralel düzenlemez.

## Kritik: aynı isimler için ekip protokolü
1. `docs/04_NAMING_CONVENTIONS.md` → tek kavram ve ad sözlüğü.
2. `docs/05_DATA_DICTIONARY.md` → entity/alan/tip sözleşmesi.
3. `docs/06_API_CONTRACT.md` → URI/DTO/JSON sözleşmesi.
4. **Contract owner = iki kişi birlikte**; hiçbir Codex tek başına bir adı değiştirip diğerinin kullandığını geçersiz kılamaz.
5. Yeni isim/alan/endpoint teklifi: **proposal → iki kişi onayı → 04+05+06 tek PR → main merge → ikisi de pull → kod implementasyonu**.
6. Doküman uyuşmazlığında **dur ve raporla**. “Çalışsın diye farklı bir endpoint ekleme” yasak.
7. PR açıklamasında açık alan: `Contract changed? Yes/No`; Yes ise kimin onayladığı ve etkilenen istemciler.

## Git ve Codex akışı
- Varsayılan `main` korunur; task/feature branchlerde çalış: `feature/client-meal-logs`, `feature/dietitian-client-list`, `docs/contracts`, `fix/...`.
- Önce `git pull` ile main güncelle; görevin kapsamını ve ilgili dosya sahipliğini kontrol et.
- Codex'e **tek görev**, kısa ve test edilebilir hedef, değiştirilecek alan, kullanılacak belgeler ve `başka bir şey yapma` sınırı ver.
- Codex raporunu diğer geliştiriciyle paylaş; build/test ve contract etkisi incelensin; küçük PR/commit ile birleştir.
- Aynı branch'i aynı anda farklı Codex oturumlarına yazdırma. Geniş refactor/taşıma ayrı onaylı görev.

## Önerilen geliştirme sırası (mimari onaydan sonra)
1. **Karar ve sözleşmeler:** teknoloji, rol, ilişki kuralı, API/şema onayı; mock örnekleri ve UI tasarım yönü.
2. **Temel altyapı:** ayrı uygulama iskeletleri, backend DB bağlantısı, kimlik ve rol testleri.
3. **Ana ürün döngüsü:** mobil manuel öğün/su → API → webde diyetisyen görüntüsü → web plan atama → mobil plan ekranı.
4. **Gelişim/ölçüm/aktivite:** kayıt ve grafikler; veri kaynağı izleri.
5. **AI fotoğraf:** görüntü upload → tahmin → kullanıcı düzeltmesi → öğün kaydı; kalori belirsizliği ve test raporu.
6. **Lab:** veri girişi ve referans bazlı kurallar → rapor görünümü → veri uygunsa ML araştırma prototipi.
7. **Entegrasyon:** cihaz senkronizasyonu (izinler, platform kısıtları), bildirimler (kapasiteye göre).
8. **Kalite/yayın:** E2E, güvenlik, KVKK, performans, mağaza hazırlığı. Gerçek yayın ayrı kontrol kapısından geçer.

## Karar defteri
| Karar | Mevcut durum | Onay / sonraki işlem |
|---|---|---|
| Yeni repo/klasör adı `smart-nutrition-platform` | **ONAYLI** | Değiştirme |
| Eski fitness kod/dokümanlarının kullanılmaması | **ONAYLI** | Sıfırdan geliştirme |
| Ürün yönü: diyetisyen odaklı; mobil danışan + web uzman + backend | **ONAYLI** | Özellik detayları zamanla doğrulanacak |
| Görsel yemek ve tahlil AI ortak çalışma | **ONAYLI** | Görev bazlı tek PR lideri |
| Belgelerin `docs/` içinde, `AGENTS.md`/`README.md` kökte olması | **ONAYLI** | 12+2 belge |
| Codex ortak naming/data/API sözleşmesi | **ONAYLI PRENSİP** | Bu dosyalar kabul edilince isimler sabitlenir |
| Flutter/React TS/ASP.NET Core/PostgreSQL/Python önerisi | **AÇIK** | Teknolojileri birlikte onaylayın |
| Tek aktif diyetisyen ve tek aktif plan kuralı | **AÇIK** | Ürün/DB kararı |
| Kimlik/auth backend modül lideri Uğur önerisi | **AÇIK** | İki kişi teyit |
| Tasarım renk paleti, dark/light tercihi | **AÇIK** | Mobil 2–3 ekran tasarım onayı |
| Besin kataloğu kaynağı/lisans, AI modeli/veri | **AÇIK** | Kaynak araştırma ve validasyon |
| Health Connect / HealthKit kapsamı | **AÇIK** | Platform/cihaz testi |
| Lab test standartları, birim dönüşümleri ve OCR | **AÇIK** | Güvenli kural tasarımı |
| Gerçek kullanıcıya açılış/yayın | **KAPI** | `11_SECURITY_AND_RELEASE.md` tamamlanmalı |

## İlk Codex görevi (kod yazdırmadan)
> `AGENTS.md`, `README.md` ve `docs/` altındaki 12 dosyayı oku. `04_NAMING_CONVENTIONS.md`, `05_DATA_DICTIONARY.md`, `06_API_CONTRACT.md` arasındaki isim/alan/rota uyuşmazlıklarını ve `12_TEAM_PLAN_AND_DECISIONS.md` içindeki açık kararları raporla. Kod yazma, dosya oluşturma veya değiştirme. Sadece kısa, somut rapor ver.

## Definition of Done — her feature için
- İş akışı ve istek kapsamı karşılandı; alakasız dosya değişmedi.
- Kanonik adlar ve API sözleşmesiyle uyumlu; contract etkisi açık raporlandı.
- İlgili lint/build/test çalıştırıldı; başarısızlık gizlenmedi.
- Yetki, veri sahipliği, tıbbi belirsizlik ve kişisel veri kuralları kontrol edildi.
- Mobil/web karşılıklı etkilendiğinde diğer geliştiriciye entegrasyon notu verildi.
