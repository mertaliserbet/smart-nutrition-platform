import 'package:flutter/material.dart';

import 'health_data_api.dart';

class HealthSyncSection extends StatelessWidget {
  const HealthSyncSection({
    required this.busy,
    required this.consent,
    required this.loaded,
    required this.connection,
    required this.summary,
    required this.message,
    required this.pending,
    required this.onConsent,
    required this.onRefresh,
    required this.onSync,
    required this.onToggle,
    required this.onDiscard,
    required this.providerLabel,
    super.key,
  });
  final bool busy, consent, loaded, pending;
  final String providerLabel;
  final WearableConnection? connection;
  final ActivityDailySummary? summary;
  final String? message;
  final ValueChanged<bool> onConsent;
  final VoidCallback onRefresh, onSync, onToggle, onDiscard;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Hesabınızdaki aktivite verileri',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          Text('Aktarım kaynağı: $providerLabel'),
          const Text(
            'Aktarım yalnız düğmeye bastığınızda yapılır. Aktarımı durdurmak '
            'önceki kayıtları silmez. Her aktarım öncesinde cihaz okuma erişimi yeniden kontrol edilir.',
          ),
          if (!loaded)
            const Text('Sunucu bilgileri henüz yüklenmedi.')
          else if (connection == null)
            const Text('Bu sağlayıcı için henüz aktarım bağlantısı yok.')
          else ...[
            Text(
              connection!.status == 'active'
                  ? 'Sunucuya aktarım tercihi açık.'
                  : 'Sunucuya aktarım durduruldu.',
            ),
            Text(
              connection!.lastSyncedAt == null
                  ? 'Henüz başarılı senkronizasyon yok.'
                  : 'Son başarılı senkronizasyon: ${_date(connection!.lastSyncedAt!)}',
            ),
            Text(switch (connection!.lastSyncStatus) {
              'failed' => 'Sunucunun son deneme durumu: başarısız.',
              'succeeded' => 'Sunucunun son deneme durumu: başarılı.',
              _ => 'Sunucuda henüz aktarım denemesi yok.',
            }),
          ],
          CheckboxListTile(
            key: const ValueKey('health-transfer-consent'),
            contentPadding: EdgeInsets.zero,
            title: const Text(
              'Okunabilen sağlık kayıtlarımın hesabıma aktarılmasını onaylıyorum.',
            ),
            value: consent,
            onChanged: busy ? null : (v) => onConsent(v == true),
          ),
          OutlinedButton(
            onPressed: busy ? null : onRefresh,
            child: const Text('Sunucu verilerini yenile'),
          ),
          FilledButton(
            onPressed: busy || !consent || connection?.status == 'revoked'
                ? null
                : onSync,
            child: Text(
              pending
                  ? 'Aynı aktarımı yeniden dene'
                  : 'Bugünü oku ve senkronize et',
            ),
          ),
          if (pending)
            TextButton(
              onPressed: busy ? null : onDiscard,
              child: const Text(
                'Bekleyen denemeyi bırak; yeniden hazırlanacak',
              ),
            ),
          if (connection != null)
            OutlinedButton(
              onPressed: busy || (connection!.status == 'revoked' && !consent)
                  ? null
                  : onToggle,
              child: Text(
                connection!.status == 'active'
                    ? 'Sunucuya aktarımı durdur'
                    : 'Sunucuya aktarımı yeniden aç',
              ),
            ),
          if (message != null) Text(message!),
          if (summary != null) ...[
            const SizedBox(height: 12),
            Text(
              'Sunucuda hesaplanan özet: ${_date(summary!.from).split(' ').first}',
            ),
            for (final entry in const {
              'steps': 'Adım',
              'distanceKm': 'Mesafe (km)',
              'exerciseMinutes': 'Egzersiz (dk)',
              'activeEnergyKcal': 'Aktif enerji (kcal)',
              'heartRateMeanBpm': 'Ortalama nabız (atım/dk)',
            }.entries)
              Text('${entry.value}: ${_value(summary!.values[entry.key])}'),
            if (summary!.isPartial)
              Text(
                'Özet kısmi: ${summary!.excludedOverlapCount} örtüşen, '
                '${summary!.unallocatedCount} güne dağıtılamayan kayıt var.',
              ),
            const Text(
              'Özet hesabınızdaki tüm kaynakları kapsar; örtüşen kayıtlar sunucuda değerlendirilir. '
              'Veri yoksa sıfır üretilmez; bu özet tıbbi değerlendirme değildir.',
            ),
          ],
        ],
      ),
    ),
  );
  static String _value(num? value) => value == null
      ? 'Veri yok'
      : value == value.truncateToDouble()
      ? value.toInt().toString()
      : value.toStringAsFixed(2);
  static String _date(DateTime value) {
    final d = value.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(d.day)}.${two(d.month)}.${d.year} ${two(d.hour)}:${two(d.minute)}';
  }
}
