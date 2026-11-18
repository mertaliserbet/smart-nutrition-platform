package com.example.smart_nutrition_mobile

import androidx.health.connect.client.HealthConnectClient
import androidx.health.connect.client.permission.HealthPermission
import androidx.health.connect.client.records.*
import androidx.health.connect.client.records.metadata.Metadata
import androidx.health.connect.client.request.ReadRecordsRequest
import androidx.health.connect.client.time.TimeRangeFilter
import androidx.lifecycle.lifecycleScope
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel.Result
import java.time.Instant
import kotlinx.coroutines.launch
import kotlin.reflect.KClass

/** Read-only boundary: no aggregates, writes, locations, logging or HTTP. */
class HealthRecordReader(private val activity: FlutterFragmentActivity) {
    fun read(call: MethodCall, result: Result) {
        val from = call.argument<Number>("from")?.toLong()
        val to = call.argument<Number>("to")?.toLong()
        val type = call.argument<String>("type")
        if (from == null || to == null || from >= to || to - from > 93600000L) {
            result.error("invalid_range", "Invalid health read interval", null)
            return
        }
        activity.lifecycleScope.launch {
            try {
                if (HealthConnectClient.getSdkStatus(activity) != HealthConnectClient.SDK_AVAILABLE) {
                    result.error("unavailable", "Health Connect unavailable", null)
                    return@launch
                }
                val client = HealthConnectClient.getOrCreate(activity)
                val range = TimeRangeFilter.between(Instant.ofEpochMilli(from), Instant.ofEpochMilli(to))
                val rows = when (type) {
                    "STEPS" -> records(client, StepsRecord::class, range).map {
                        row(it.metadata, it.startTime, it.endTime, it.count, "COUNT")
                    }
                    "DISTANCE_DELTA" -> records(client, DistanceRecord::class, range).map {
                        row(it.metadata, it.startTime, it.endTime, it.distance.inMeters, "METER")
                    }
                    "ACTIVE_ENERGY_BURNED" -> records(client, ActiveCaloriesBurnedRecord::class, range).map {
                        row(it.metadata, it.startTime, it.endTime, it.energy.inKilocalories, "KILOCALORIE")
                    }
                    "WORKOUT" -> records(client, ExerciseSessionRecord::class, range).map {
                        row(it.metadata, it.startTime, it.endTime,
                            (it.endTime.toEpochMilli() - it.startTime.toEpochMilli()) / 60000.0,
                            "MINUTE") + mapOf("exerciseType" to it.exerciseType)
                    }
                    "HEART_RATE" -> records(client, HeartRateRecord::class, range).flatMap { record ->
                        record.samples.map {
                            row(record.metadata, it.time, it.time, it.beatsPerMinute, "BEATS_PER_MINUTE")
                        }
                    }
                    else -> {
                        result.error("unsupported_type", "Unsupported health type", null)
                        return@launch
                    }
                }
                result.success(rows)
            } catch (_: SecurityException) {
                result.error("permission_denied", "Health read permission required", null)
            } catch (_: Exception) {
                // Never expose a provider exception that might contain health data.
                result.error("read_failed", "Health data could not be read", null)
            }
        }
    }

    private suspend fun <T : Record> records(
        client: HealthConnectClient,
        type: KClass<T>,
        range: TimeRangeFilter,
    ): List<T> {
        val permission = HealthPermission.getReadPermission(type)
        if (permission !in client.permissionController.getGrantedPermissions()) throw SecurityException()
        val records = mutableListOf<T>()
        var token: String? = null
        do {
            val page = client.readRecords(ReadRecordsRequest(type, range, pageToken = token))
            records.addAll(page.records)
            token = page.pageToken
        } while (!token.isNullOrEmpty())
        if (permission !in client.permissionController.getGrantedPermissions()) throw SecurityException()
        return records
    }

    private fun row(metadata: Metadata, from: Instant, to: Instant, value: Number, unit: String) =
        mapOf<String, Any>(
            "id" to metadata.id,
            "sourceId" to metadata.dataOrigin.packageName,
            "from" to from.toEpochMilli(),
            "to" to to.toEpochMilli(),
            "value" to value,
            "unit" to unit,
            "recordingMethod" to metadata.recordingMethod,
        )
}
