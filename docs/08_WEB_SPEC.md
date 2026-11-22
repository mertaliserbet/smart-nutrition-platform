# 08 — Gerçek React ekranları ve web davranış

İnceleme tabanı 22.11.2026 / `4f160b3`. Route kaynağı `apps/web/src/App.tsx`, gerçek çalışma alanı DietitianWorkspace'tir. HTTP/DTO/yetki [06](06_API_CONTRACT.md), tasarım [09](09_DESIGN_SYSTEM.md), güvenlik [11](11_SECURITY_AND_RELEASE.md) içindedir.

## Route ve erişim

| Route | Gerçek davranış |
|---|---|
| / | /giris'e yönlendirme |
| /giris | Diyetisyen web oturumu; normal danışan paneli değildir |
| /kayit | /giris'e yönlendirme; eski RegistrationPage dosyası aktif web danışan kaydı değildir |
| /sifremi-unuttum | Gerçek reset talebi veya e-posta fragment tokenıyla yeni parola formu |
| /eposta-dogrulama | Kod ile doğrulama ve yeniden gönderim |
| /hesabim | Beş alanlı hesap özeti, mevcut başvuru/uzman durumuna göre geçiş ve çıkış |
| /uzman-basvurusu | Oturumsuz yeni uzman formu; mevcut danışana mobil Profil'i önerir, ancak bu mobil erişim henüz yok ([07](07_MOBILE_SPEC.md)/[12](12_TEAM_PLAN_AND_DECISIONS.md)) |
| /uzman/basvuru-durumu | Mevcut uzman başvurusu/doğrulanmışlık durumu |
| /yonetici-giris | Ayrı parola + TOTP/kurtarma kodu; yalnız yerel Development/Mailpit için e-posta kodu seçeneği |
| /yonetim, /yonetim/uzmanlar | MFA Admin uzman başvuru listesi ve onayı |
| /calisma-alani | Gerçek, doğrulanmış uzman çalışma alanı ve sınırlı gerçek dashboard |
| /calisma-alani/danisanlar | Aktif danışan listesi, arama/sıralama/sayfalama |
| /calisma-alani/danisanlar/:clientId | Temel kimlik ve bağımsız izinli sağlık/program/görev bölümleri |
| /calisma-alani/baglantilar | Davet kodu, istek kabul/red ve ilişki sonlandırma |
| /onizleme/* | Yalnız Development; sentetik WorkspacePreview, gerçek danışan alanından ayrıdır |

Çalışma alanına girişte CSRF, auth/me ve dietitians/me okunur. client temel rollü, onaylı DietitianProfile sahibi kullanıcı aynı hesabıyla diyetisyen çalışma alanına erişir; yeni diyetisyen hesabı oluşturması gerekmez. Rol adı veya başvuru yapılmış olması tek başına yetki değildir. Bekleyen uzman başvuru durumuna gider; bekleyen veya henüz onaylanmamış kullanıcıya çalışma alanı erişimi verilmez. Mevcut backend başvuru ve yetkilendirme kuralları korunur. 401 veya hesap bağlamı kaybında hassas görünüm bırakılmaz.

**Kesinleşmiş mobil geçiş:** Flutter Profil'deki **“Diyetisyen Paneline Git”**, onaylı kullanıcı için güvenilir HTTPS web adresindeki çalışma alanını harici tarayıcıda açar. Geçerli web oturumu varsa kullanılır; yoksa kullanıcı aynı e-posta/şifreyle normal web girişini yapar. Web oturumu mobilden bağımsızdır; mobil JWT/refresh token web adresine, URL'ye veya tarayıcıya aktarılmaz. Profil başvuru/durum ve bu panel seçeneği Flutter'da henüz geliştirilip doğrulanmış değildir; mevcut web başvuru metni tamamlanmış mobil akış kanıtı sayılmaz ([07](07_MOBILE_SPEC.md)).

## Gerçek danışan detayındaki bölümler

| Bölüm | Mevcut arayüz |
|---|---|
| Program | Taslak oluşturma, kendi atadığı içeriği düzenleme, açık etkinleştirme/arşivleme ve değişmez sürüm gösterimi; başkasının/kişisel programı salt okunur |
| Öğün | Kaynak/zaman, miktar ve nullable besin değerleri; tarih/sayfalama, yorum ve tek düzey cevaplar |
| Ölçüm | Kilo/bel/kalça/göğüs/yağ liste ve grafik, tarih/sıralama; sağlık yorumu/BMI türetmez |
| Görev | Atama, açıklama/son tarih düzenleme, iptal onayı, durum/tamamlama ve sayfalı snapshot geçmişi |
| Su | Seçilen gün kayıt/toplam, en çok 31 günlük grafik ve tablo; kişisel su hedefini çağırmaz |
| Program–tüketim | Açık sürüm/gün seçimi; bilinen toplam/eksik değerler ve yalnız uygun koşullarda kayıtlı kcal farkı |

Güncel web aktivite/laboratuvar görünümleri sentetik önizleme bileşenleridir; gerçek diyetisyen sağlık/aktivite paylaşımı veya laboratuvar API'si yoktur. Tarif, bildirim teslimi, PDF raporu, kapsamlı kullanıcı/şikâyet/katalog/audit yönetimi tamamlanmış panel sayılmaz.

## İstek ve etkileşim davranışı

Web same-origin HTTPS cookie taşır; JWT login/refresh'i kullanmaz. CSRF ve hesap özeti yalnız geçici bellektedir. Cookie/CSRF/hesap taşıma ayrıntısı ve süreler [06](06_API_CONTRACT.md)'dadır.

Danışan/oturum/gün/sürüm/filtre değişince eski veri ve sayılar temizlenir; AbortController ve işlem kimlikleri geç yanıtı eler. 403 paylaşım kapalı, 404 kaynak/ilişki yok, yetkili boş veri ve ağ/DB hatası ayrı gösterilir; hata 0 toplam veya sentetik kayıt değildir.

Görevde 409 taslağı korur, güncel sürüm okunup açık yeniden başlatma istenir; otomatik üzerine yazma yoktur. Görev ve su bölümleri görünür sekmede 30 saniyelik/fokus/elle yenileme kullanır; gizli sekmede su içeriği kaldırılır. Bu polling bildirim teslimi veya WebSocket değildir; oturumu yaşatmak için keepalive kurulmaz. Diğer bölümlerdeki yenileme davranışı kendi bileşenine aittir.

Su okumalarının herhangi birinde 403/404 alınırsa kayıt/toplam/grafik birlikte kaldırılır. Diyetisyen danışan adına kategori izni açmaz. Ölçüm/öğün tüketimini değiştirmez veya danışan görevini tamamlamaz.

## Parola sıfırlama

Bağlantısız sayfa genel email talebi yapar. Güvenilir web origin'inden gelen `#token=` fragment'i belleğe alınır ve URL/history replace ile temizlenir; query/bozuk/tekrarlı kod reddedilir ve temizlenir. Token kalıcı depoya, router state'e, analitik/loga taşınmaz; no-referrer kullanılır. Yenilemede kod kaybolur; e-posta bağlantısını yeniden açma/yeni talep yolu gösterilir.

Formda yeni parola/tekrar, tek gönderim ve erişilebilir hata odağı vardır. Reset POST'u otomatik tekrarlanmaz. 204 sonrası /giris replace ile açılır, otomatik oturum oluşturulmaz. Admin reset MFA'yı kaldırmaz.

## Doğrulama durumu

React DOM, gerçek ağ/API/DB ve gerçek Edge HTTPS testleri ayrı düzeylerdir. Playwright senaryoları `apps/web/e2e/regression.e2e.ts` içindedir; danışan adımlarının bir kısmını API yapar, Flutter testi değildir. İki tema, dar ekran ve klavye kontrolleri tarihsel U6 raporunda yer alır; bu görevde yeniden çalıştırılmadı.

Kurulum/test komutları [kök README](../README.md), tarih/commit/kapsamla sınırlı geçmiş raporlar [12](12_TEAM_PLAN_AND_DECISIONS.md)'dedir.
