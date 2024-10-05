package com.example.currency_converter

import com.example.currency_converter.R 
import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews
import android.content.SharedPreferences
import org.json.JSONObject

class CurrencyWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray) {
        for (appWidgetId in appWidgetIds) {
            updateAppWidget(context, appWidgetManager, appWidgetId)
        }
    }

    companion object {
        private const val PREFS_NAME = "CurrencyConverterPrefs"
        private const val RATES_KEY = "exchangeRates"
        private const val FROM_CURRENCY_KEY = "fromCurrency"
        private const val TO_CURRENCY_KEY = "toCurrency"
        private const val AMOUNT_KEY = "amount"

        fun updateAppWidget(context: Context, appWidgetManager: AppWidgetManager, appWidgetId: Int) {
            val views = RemoteViews(context.packageName, R.layout.currency_widget)

            // Get saved data
            val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            val ratesJson = prefs.getString(RATES_KEY, null)
            val fromCurrency = prefs.getString(FROM_CURRENCY_KEY, "AED") ?: "AED"
            val toCurrency = prefs.getString(TO_CURRENCY_KEY, "INR") ?: "INR"
            val amount = prefs.getString(AMOUNT_KEY, "1.00") ?: "1.00"

            // Set up click intent for the whole widget
            val intent = Intent(context, MainActivity::class.java)
            val pendingIntent = PendingIntent.getActivity(context, 0, intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
            views.setOnClickPendingIntent(R.id.widget_layout, pendingIntent)

            // Update UI
            views.setTextViewText(R.id.from_currency_text, fromCurrency)
            views.setTextViewText(R.id.to_currency_text, toCurrency)
            views.setTextViewText(R.id.amount_input, amount)

            // Perform conversion
            if (ratesJson != null) {
                val rates = JSONObject(ratesJson)
                val result = convertCurrency(amount.toDouble(), fromCurrency, toCurrency, rates)
                views.setTextViewText(R.id.result_text, String.format("%.2f", result))
            } else {
                views.setTextViewText(R.id.result_text, "N/A")
            }

            // Update the widget
            appWidgetManager.updateAppWidget(appWidgetId, views)
        }

        private fun convertCurrency(amount: Double, from: String, to: String, rates: JSONObject): Double {
            val eurValue = amount / rates.getDouble(from)
            return eurValue * rates.getDouble(to)
        }
    }
}