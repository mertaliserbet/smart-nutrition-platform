package com.example.smart_nutrition_mobile

import android.app.Activity
import android.os.Bundle
import android.widget.Button
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView

/** Public permission rationale only; never shows account or health records. */
class HealthPermissionsActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        title = "Sağlık verisi izinleri"
        val content = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            val padding = (24 * resources.displayMetrics.density).toInt()
            setPadding(padding, padding, padding, padding)
            addView(TextView(context).apply {
                textSize = 18f
                text = "Smart Nutrition – Cihaz sağlık verileri\n\n" +
                    "Adım, mesafe, egzersiz, aktif kalori ve varsa nabız kayıtları, " +
                    "yalnız seçtiğiniz okuma izinleriyle cihazda görüntülenir. " +
                    "Cihazdaki sağlık deposuna veri yazılmaz. Açık aktarım onayınızla " +
                    "okunabilen kayıtlar hesabınıza senkronize edilebilir; otomatik aktarım yapılmaz. " +
                    "Cihazdan okunan yerel kopyalar ekranın belleğinde tutulur; " +
                    "ekran kapatıldığında, uygulamadan ayrılınca veya oturum değişince temizlenir.\n\n" +
                    "Sunucuya aktarılan kayıtlar hesabınızda saklanır; aktarımı durdurmak geçmişi silmez.\n\n" +
                    "İzin vermeden uygulamanın diğer özelliklerini kullanabilirsiniz. " +
                    "Her veri türünün iznini Health Connect > Uygulama izinleri " +
                    "bölümünden değiştirebilir veya geri alabilirsiniz. " +
                    "Cihazdaki sağlık deposu telefonun kullanıcısına aittir; " +
                    "paylaşılan cihazda kayıtların size ait olduğundan emin olun."
            })
            addView(Button(context).apply {
                text = "Kapat"
                setOnClickListener { finish() }
            })
        }
        setContentView(ScrollView(this).apply { addView(content) })
    }
}
