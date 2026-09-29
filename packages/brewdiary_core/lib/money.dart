// Money — a port of src/lib/money.ts. Currency is a property of the PLACE, not the
// app. Formatting goes through intl so grouping and symbol placement are correct per
// locale: ₹1,23,456 in India (lakhs), €1.234,56 in Germany, $1,234.56 in the US.
import 'package:intl/intl.dart';

const currencyByCountry = <String, String>{
  'IN': 'INR', 'US': 'USD', 'GB': 'GBP', 'IE': 'EUR', 'FR': 'EUR', 'DE': 'EUR',
  'ES': 'EUR', 'IT': 'EUR', 'NL': 'EUR', 'FI': 'EUR', 'AU': 'AUD', 'CA': 'CAD',
  'NZ': 'NZD', 'SG': 'SGD', 'JP': 'JPY', 'KR': 'KRW', 'TH': 'THB', 'NO': 'NOK',
  'SE': 'SEK', 'PL': 'PLN', 'TR': 'TRY', 'ZA': 'ZAR', 'BR': 'BRL', 'MX': 'MXN',
  'AE': 'AED',
};

const defaultCurrency = 'INR';

/// Every currency the pickers offer (the values of the table, de-duplicated).
final supportedCurrencies = currencyByCountry.values.toSet().toList()..sort();

String currencyForCountry(String? country) => currencyByCountry[(country ?? '').toUpperCase()] ?? defaultCurrency;

const _zeroDecimal = {'JPY', 'KRW'};

String _localeFor(String code) {
  switch (code) {
    case 'INR':
      return 'en_IN';
    case 'USD':
      return 'en_US';
    case 'GBP':
      return 'en_GB';
    case 'EUR':
      return 'de_DE';
    case 'JPY':
      return 'ja_JP';
    case 'KRW':
      return 'ko_KR';
    case 'THB':
      return 'th_TH';
    case 'AUD':
      return 'en_AU';
    case 'CAD':
      return 'en_CA';
    case 'BRL':
      return 'pt_BR';
    default:
      return 'en_US';
  }
}

bool _known(String code) => supportedCurrencies.contains(code);

/// Format an amount in a currency, by that currency's own conventions. Falls back to
/// a bare number rather than throwing if a currency code is unknown.
String formatMoney(num amount, [String currency = defaultCurrency, bool round = false]) {
  final code = (currency.isEmpty ? defaultCurrency : currency).toUpperCase();
  final isInt = amount == amount.roundToDouble();
  final digits = _zeroDecimal.contains(code) || round ? 0 : (isInt ? 0 : 2);
  if (!_known(code)) {
    return digits == 0 ? amount.round().toString() : amount.toStringAsFixed(2);
  }
  try {
    final f = NumberFormat.simpleCurrency(locale: _localeFor(code), name: code, decimalDigits: digits);
    return f.format(amount);
  } catch (_) {
    return '$amount';
  }
}

/// Just the symbol, for a tight spot like an input prefix.
String currencySymbol([String currency = defaultCurrency]) {
  final code = currency.toUpperCase();
  if (!_known(code)) return code;
  try {
    return NumberFormat.simpleCurrency(locale: _localeFor(code), name: code).currencySymbol;
  } catch (_) {
    return code;
  }
}

// ── flexing a tab: a BAND, never the figure ──────────────────────────────────
const _bandStep = <String, int>{
  'INR': 500, 'JPY': 3000, 'KRW': 30000, 'THB': 500, 'ZAR': 250, 'MXN': 250,
  'BRL': 100, 'TRY': 500, 'NOK': 250, 'SEK': 250, 'PLN': 100, 'AED': 100,
};
const _defaultStep = 25;

/// The band a tab falls in, as a display string: "₹2,500+". NEVER show a flexed tab
/// as an exact figure — the precision is the harm, not the amount.
String spendBand(num amount, [String currency = defaultCurrency]) {
  final code = currency.toUpperCase();
  final step = _bandStep[code] ?? _defaultStep;
  final bands = [1, 2, 5, 10, 20].map((m) => m * step).toList();
  if (amount.isNaN || amount.isInfinite || amount < bands.first) {
    return 'under ${formatMoney(bands.first, code, true)}';
  }
  final floor = bands.where((b) => amount >= b).last;
  return '${formatMoney(floor, code, true)}+';
}
