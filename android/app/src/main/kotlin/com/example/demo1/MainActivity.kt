package com.example.demo1

import android.Manifest
import android.app.Activity
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.os.Build
import android.telephony.SmsManager
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicInteger

class MainActivity : FlutterFragmentActivity() {
    private val channelName = "saferun/sms"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "hasPermission" -> result.success(hasSendPermission())
                    "sendSms" -> {
                        val phone = call.argument<String>("phone")
                        val message = call.argument<String>("message")
                        if (phone.isNullOrBlank() || message.isNullOrBlank()) {
                            result.error("INVALID_ARGS", "Phone and message are required", null)
                        } else {
                            sendSms(phone, message, result)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun hasSendPermission(): Boolean {
        return checkSelfPermission(Manifest.permission.SEND_SMS) ==
            PackageManager.PERMISSION_GRANTED
    }

    @Suppress("DEPRECATION")
    private fun legacySmsManager(): SmsManager {
        return SmsManager.getDefault()
    }

    private fun smsManager(): SmsManager {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            getSystemService(SmsManager::class.java)
        } else {
            legacySmsManager()
        }
    }

    /**
     * Sends the text straight from the phone (no screen opens).
     * Long texts are split and each part is sent on its own, which needs
     * only the SEND_SMS permission. The result is reported back only after
     * the phone's radio has accepted every part.
     */
    private fun sendSms(phone: String, message: String, result: MethodChannel.Result) {
        if (!hasSendPermission()) {
            result.error("NO_PERMISSION", "SEND_SMS permission is not granted", null)
            return
        }
        try {
            val sms = smsManager()
            val parts = sms.divideMessage(message)
            val action = "com.example.demo1.SMS_SENT_" + System.nanoTime()
            val remaining = AtomicInteger(parts.size)
            val failed = AtomicBoolean(false)
            val replied = AtomicBoolean(false)

            val receiver = object : BroadcastReceiver() {
                override fun onReceive(context: Context?, intent: Intent?) {
                    if (resultCode != Activity.RESULT_OK) {
                        failed.set(true)
                    }
                    if (remaining.decrementAndGet() == 0) {
                        try {
                            unregisterReceiver(this)
                        } catch (_: Exception) {
                        }
                        if (replied.compareAndSet(false, true)) {
                            if (failed.get()) {
                                result.error(
                                    "SEND_FAILED",
                                    "The network did not accept the message",
                                    null
                                )
                            } else {
                                result.success(true)
                            }
                        }
                    }
                }
            }

            val filter = IntentFilter(action)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                registerReceiver(receiver, filter, Context.RECEIVER_NOT_EXPORTED)
            } else {
                registerReceiver(receiver, filter)
            }

            val flags = PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_ONE_SHOT
            for ((index, part) in parts.withIndex()) {
                val sentIntent = PendingIntent.getBroadcast(
                    this,
                    index,
                    Intent(action).setPackage(packageName),
                    flags
                )
                sms.sendTextMessage(phone, null, part, sentIntent, null)
            }
        } catch (e: Exception) {
            result.error("SEND_FAILED", e.message ?: "Could not send the message", null)
        }
    }
}