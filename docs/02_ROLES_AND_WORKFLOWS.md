# 02 — Roller, izinler ve kullanıcı akışları

**Kanonik roller:** `Client`, `Dietitian`, `Admin`. API rol değerleri `client`, `dietitian`, `admin` (bkz. `04_NAMING_CONVENTIONS.md`).

Ürün kuralları `12`deki 22 karara dayanır; aşağıdaki akışlar `05/06`daki açık DTO'ları kesinleştirmez. İlk sürüm web yönetim paneli ile öğün yorum/cevap/bildirim koşulları geçerlidir; diğer onaylı özelliklerin takvimi `01/12`de ayrılır.

## Yetki matrisi (taslak)
| İşlem | Client | Dietitian | Admin |
|---|---|---|---|
| Kendi profilini/sağlık verilerini görüntüleme | Evet | Kendi profilini | Kural gerektiren sınırlı yönetim |
| Kendi yemek/su/ölçüm/aktivite/lab kaydı | Oluştur/düzenle/sil | Danışanın yerine değiştiremez | Hayır |
| Diyetisyen ilişki talebi | Talep et/sonlandır | Kabul/red/sonlandır | Denetle (istisnai) |
| Danışanın paylaşılmış kayıtları | Kendi kayıtları; diyetisyen gerekmez | **Doğrulanmış uzman + aktif ilişki + kategori izni**; tahlilde ayrıca açık onay | Varsayılan hayır |
| Beslenme programı | Kendi kişisel programını oluştur/düzenle; atanmış programı/hedefleri salt okunur gör | Yalnız kendi atadığı programı aktif/yetkili ilişkiyle oluştur/atama/düzenle | Varsayılan hayır |
| Öğün yorumları/cevaplar | Kendi öğününde | Erişimine izin verilmiş öğünde | Varsayılan hayır |
| Görev | Kendi görevini izle; durum geçiş yetkisi açık | Yetkili danışana ata; kendi atadığı görevi yönet | Varsayılan hayır |
| Kategori izni/tahlil açık onayı | Kendi paylaşımını/onayını ver veya geri çek | Danışan adına izin açamaz | Danışan adına izin açamaz |
| Hesap/yetki operasyonu | Kendi hesap silme | Kendi hesap tercihleri | Yetkili idari işlem |

Yönetici, “tüm laboratuvar sonuçlarını istediği gibi görür” varsayımıyla tasarlanmaz. Minimum erişim; istisnai destek erişiminde gerekçe ve audit zorunluluğu. Admin yönetim oturumunda MFA gerekir; ilk sürüm yönetim paneli webdedir. Rıza, kategori izni ve cihaz/OS izni birbirinin yerine geçmez.

## Akış A — ilk kullanım
1. E-posta/şifre ile hesap, e-posta doğrulama, güvenli oturum ve şifre sıfırlama akışları bulunur. Diyetisyen mobil/web üzerinden başvurur; Admin doğrular. Başvuru veya rol seçimi doğrulanmış uzman/veri erişim yetkisi vermez. Admin MFA zorunludur; ayrıntılı oturum/başvuru DTO'ları açıktır.
2. Gizlilik bilgilendirmesi ve gerekli açık rıza işlemleri ayrı tutulur; zorunlu olmayan iznin reddi temel işlemleri mümkün olduğunca engellemez.
3. Danışan ölçüm/hedef (isteğe bağlı) girer; diyetisyen bağlamadan günlük takip ve kişisel program oluşturma yapabilir. Kişisel kalori/makro/su önerileri düzenlenebilir; öneri hesaplama yöntemi açıktır.
4. Diyetisyen arama veya davet koduyla ilişki isteği başlatılır; karşılıklı onay gerekir. En fazla bir aktif diyetisyen sınırı sunucuda korunur; kod kullanımı tek başına onay veya paylaşım izni değildir. Başka danışan verisi görünmez; geçmiş ilişki korunur.

## Akış B — yemek kaydı
1. Manuel besin girişi veya fotoğraf çekimi/seçimi.
2. AI sonucu: tahmin edilen besin(ler), porsiyon/gram belirsizliği, tahmini enerji ve makrolar.
3. Kullanıcı besin/miktarı kontrol eder, gerektiğinde değiştirir; açık onayından sonra ayrı `MealLog` kaydedilir. Katalog (`FoodItem`) ve özel tarif (`Recipe`) bağlantıları mevcut sözleşmeye uyar; tarif bileşen yapısı açıktır.
4. Doğrulanmış diyetisyen, aktif ilişki ve ilgili kategori izniyle güncellenen kaydı web panelinde görür. İlk sürüm öğün yorum/cevap/bildirim akışı bu yetkileri korur; bildirim kanalı/tercihleri ayrıca kararlaştırılır. Anlık WebSocket veya push varsayılmaz.
5. Düzenleme/silmede diyetisyen görünümü güncel durumu yansıtır; audit politikası uygulanır.

## Akış C — beslenme planı
1. Diyetisyen aktif ve yetkili danışanı seçer; danışan ise diyetisyen olmadan kendi kişisel `NutritionPlan`ını oluşturabilir. Kişisel programda `dietitianId` boş, atanmış programda yetkili diyetisyenin profil kimliğidir.
2. Program öğün önerileri/alternatifleri, hedefler ve tarih aralığıyla hazırlanır. Danışan kişisel programını düzenler; diyetisyen yalnız kendi atadığı programı düzenler. Diyetisyen hedefleri danışana salt okunurdur.
3. Kişisel/atanmış toplamında en fazla bir program aktif olabilir; ikinci aktivasyon mevcut `06` kuralıyla `409` verir. Program değiştirme/arşivleme ve ilişki bitişindeki davranış açıkken sessizce eski program arşivlenmez veya sahipliği değiştirilmez.
4. Danışan gerçek tüketimini programdan bağımsız kaydeder; hedef/tüketim karşılaştırılır. Tüketim–program eşleştirmesi zorunlu değildir; yöntem ve uyum hesabı ayrıca onaylanır.
5. Program revizyonlarında geçmiş sürüm, hedef ve alternatifler korunur; yalnız güncel satırı değiştirmek yeterli değildir. Geçmiş saklama gereksinimi onaylıdır; fiziksel sürüm/alternatif yapısı ve tam DTO'lar `05/06`da açıktır.

## Akış D — tahlil kaydı
1. Danışan `LabReport` kaydı açar; `LabResult` değerlerini tarih, birim, test adı ve rapor referans aralığı ile ekler.
   Manuel girişin ardından PDF/fotoğraf OCR aşaması onaylıdır; OCR taslağını kullanıcı kontrol edip onaylamadan kalıcı tahlil/değerlendirme oluşmaz. Diyetisyenin yardımcı incelemesi kullanıcı onayının yerine geçmez; taslak/onay kanıtının yapısı açıktır.
2. Sistem ölçümle referansı karşılaştırır, mümkün değilse `unknown` döner.
3. AI varsa yalnızca açıklayıcı/kanıtlanabilir metin üretir; tanı veya tedavi önermez.
4. Diyetisyenin tahlil erişimi aktif ilişki, ilgili kategori izni ve ayrıca geri çekilmemiş açık onaya bağlıdır. Genel gizlilik kabulü yeterli değildir. Sağlık uzmanına başvurma yönlendirmesi tanı veya otomatik acil eşik üretmez; güvenilir birim/referans olmadan kesin yorum yapılmaz.

## Akış E — aktivite
Danışan yürüyüş, koşu, bisiklet gibi aktiviteleri manuel kaydeder. Health Connect/HealthKit üzerinden desteklenen platform/izinlerle adım, mesafe, egzersiz, süre, aktif kalori ve nabız aktarımı onaylıdır; entegrasyonun yayın takvimi açıktır. Kaynak/bağlantı ve dış kimlik korunur; tekrar aktarım ve manuel/cihaz örtüşmeleri çift sayılmaz. Manuel giriş sürer, izin geri çekilince yeni sync durur. Tüm saatlerin doğrudan desteği, adım/nabız modeli veya genel caloriesKcal alanının aktif kalori olduğu varsayılmaz.

## Akış F — yorum, görev ve raporlama

- Danışan veya yetkili diyetisyen aynı öğüne yorum/cevap bırakır; başka danışanın öğününe bağlanamaz. İlk sürüm yorum/cevap/bildirim şarttır, ayrı sohbet sonraki sürümdedir. Kanonik yorum modeli ve düzenleme/silme/moderasyon ayrıntıları açıktır.
- Diyetisyen `ClientTask` atar; son tarih ve durum izlenir, hatırlatma isteğe bağlıdır. Danışanın durum geçişleri ve deadline/hatırlatma DTO'su onaylanmadan keyfî task status üretilmez.
- Grafik, program uyumu ve PDF raporu yalnız izinli veriyi içerir. Tahlil onayı PDF/analiz için de geçerlidir; rapor erişimi izin geri çekmeyi aşamaz. PDF raporu onaylı kapsamdır; ilk sürüm teslim tarihi ve uyum formülü kesinleşmiş değildir.

## Onaylı kurallar ve açık ayrıntılar

Tek aktif diyetisyen/program, kişisel program, sürüm/alternatif geçmişi, kategori bazlı paylaşım ve tahlil açık onayı onaylıdır. İlişki bitince diyetisyenin yeni erişimi kesilir; danışanın kendi verisine erişimi sürer. Saklama/silme süresi ve audit politikası `11`e göre ayrıca netleşir.

Kategori kodları, onay kanıtı, program geçişi, yorum/görev ve başvuru/davet DTO'ları, Auth/MFA ve rapor içeriği gibi açıklar için `12`nin geliştirmeye hazırlık tablosu kullanılır. Bu belge akış tanımlar; ortak sözleşmedeki açık alanları tamamlamış sayılmaz.
