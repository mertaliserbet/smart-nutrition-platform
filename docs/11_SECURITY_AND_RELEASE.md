# 11 — Güvenlik, KVKK, kalite ve gerçek yayın hazırlığı

**Bu doküman hukuki görüş değildir.** Gerçek kullanıcı verisi işlemeye ve Türkiye/Google Play dağıtımına geçmeden önce yetkin hukuk, sağlık ve mağaza politikası incelemesi gerekir. Laboratuvar ve sağlık verisi özel nitelikli kişisel veri olabilir.

## Veri koruma tasarım ilkeleri
- Veri envanteri: hangi veriler (beslenme, tahlil, ölçüm, cihaz), amaç, hukuki dayanak, saklama süresi, erişen rol, üçüncü taraf, yurt dışı aktarım.
- Aydınlatma metni ile **açık rıza gerekebilen işlemleri** birbirinden ayır; rıza gerekip gerekmediği hukuken değerlendirilir, tüm süreçleri tek checkbox ile çözme.
- **Varsayılan gizlilik:** diyetisyen yalnız aktif ve yetkili danışanı görür, admin sağlık içeriğini varsayılan göremez.
- Hesap silme, veri indirme / silme talepleri, yedekten silme ve saklama süreleri yayından önce netleşir.
- Kullanıcı fotoğrafı/tahlili AI/üçüncü tarafa aktarılıyorsa sağlayıcı, yer, sözleşme, retention ve yasal dayanak incelenir.
- Sırlar `.env` vb. yerel konfigürasyonda; git'e secret, gerçek laboratuvar sonucu veya gerçek hesap dökümü eklenmez.

## Teknik güvenlik kontrolü
| Kontrol | Kabul yönü |
|---|---|
| Kimlik | güçlü parola hash, token ömrü, refresh iptali, rate limit |
| Yetki | her endpointte rol + kaynak sahipliği + aktif ilişki testi |
| Sağlık verisi | TLS, aktarım/depoda güvenlik, en az ayrıcalık, audit |
| İstemci | güvenli token saklama; ekran/log/cache ile veri sızıntısını sınırlama |
| Dosyalar | MIME/limit/zararlı içerik taraması, private storage, süreli erişim |
| Hata/log | PII/sağlık değeri/token sızmaması, request ID |
| AI | kullanıcı izni, model sınırı, verinin gereksiz depolanmaması |
| Cihaz API'leri | açık izin, veri kapsamı, geri çekme, dedup |

## Test stratejisi
1. Domain unit test: kalori toplamı, birimler, referans aralığı, bağlantı/plan kuralları.
2. API integration/contract test: `04/05/06` sözleşmesi, 401/403/404, izole danışan verisi, giriş/çıkış.
3. Mobil/web E2E: danışan öğün girer → diyetisyen görür → plan atar → mobilde görünür.
4. AI: model versiyonu, hata durumları, belirsizlik, yanlış tahmin düzeltme, manuel fallback.
5. Güvenlik: yetkisiz farklı client ID denemeleri, dosya sınırları, rate limit.
6. UX: erişilebilirlik, küçük ekran, zayıf internet, izin reddi, çevrimdışı hata yönetimi.

## Yayın öncesi kalite kapıları
- [ ] Gerçek veri işleme ve pazara çıkış için KVKK/veri sorumlusu/yurt dışı aktarım değerlendirmesi tamam.
- [ ] Kullanıcı sözleşmeleri, gizlilik/aydınlatma, izinler ve gerekli açık rıza akışları hazır.
- [ ] Play Console sağlık politikaları, veri güvenliği beyanı ve izin gerekçeleri kontrol edildi.
- [ ] Uygulamanın sağlık iddiaları ve olası tıbbi cihaz mevzuatı riski uzmanla değerlendirildi.
- [ ] Erişim kontrolü, hesap silme, veri saklama, audit ve hata izleme test edildi.
- [ ] AI sonuçları kesinlik iddiası taşımıyor; açıklama ve onay akışları doğru.
- [ ] İmzalı release, paket kimliği, ikon, mağaza görselleri, çökme izleme ve destek kanalı hazır.
- [ ] İstemci/servis dağıtımı için gerçek ortam konfigürasyonu, secret yönetimi, yedekleme/geri yükleme ve izleme hazır.

**MVP demo ile canlı yayın farklı aşamalardır.** Demo için sentetik veri kullanılabilir; gerçek kullanıcıya açma ancak bu kapılar tamamlandıktan sonra düşünülür.
