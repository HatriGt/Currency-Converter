import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  runApp(const CurrencyConverterApp());
}

class CurrencyConverterApp extends StatelessWidget {
  const CurrencyConverterApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Currency Converter',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        scaffoldBackgroundColor: Colors.grey[50],
        fontFamily: 'Roboto',
      ),
      home: const CurrencyConverterScreen(),
    );
  }
}

class CurrencyConverterScreen extends StatefulWidget {
  const CurrencyConverterScreen({super.key});

  @override
  _CurrencyConverterScreenState createState() => _CurrencyConverterScreenState();
}

class _CurrencyConverterScreenState extends State<CurrencyConverterScreen> {
  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _convertedController = TextEditingController();
  String _fromCurrency = 'AED';
  String _toCurrency = 'INR';
  bool _isLoading = true;
  bool _isOffline = false;
  
  final List<String> _currencies = ['USD', 'TRY', 'INR', 'EUR', 'AED'];
  
  final Map<String, double> _fallbackRates = {
    'EUR': 1,
    'TRY': 37.67,
    'INR': 92.27,
    'AED': 4.03,
    'USD': 1.10
  };

  Map<String, double> _exchangeRates = {};

  Future<void> _updateWidget() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString('fromCurrency', _fromCurrency);
  await prefs.setString('toCurrency', _toCurrency);
  await prefs.setString('amount', _amountController.text);
  await prefs.setString('exchangeRates', json.encode(_exchangeRates));

  // Trigger widget update
  const platform = MethodChannel('com.example.currency_converter/widget');
  try {
    await platform.invokeMethod('updateWidget');
  } on PlatformException catch (e) {
    print("Failed to update widget: '${e.message}'.");
    }
  }

  @override
  void initState() {
    super.initState();
    _amountController.text = '1.00';
    _loadExchangeRates();
  }

  Future<void> _loadExchangeRates() async {
    setState(() {
      _isLoading = true;
      _isOffline = false; // Reset offline status
    });
    
    try {
      await _fetchExchangeRates();
    } catch (e) {
      print('Error fetching rates: $e');
      await _handleOfflineRates();
    }
    
    _convertCurrency(true);  // Add the missing argument here
    
    setState(() {
      _isLoading = false;
    });
  }

  Future<void> _fetchExchangeRates() async {
    try {
      final response = await http.get(Uri.parse(
          'https://cdn.jsdelivr.net/npm/@fawazahmed0/currency-api@latest/v1/currencies/eur.json'));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() {
          _exchangeRates = {
            'EUR': 1,
            'TRY': data['eur']['try'],
            'INR': data['eur']['inr'],
            'AED': data['eur']['aed'],
            'USD': data['eur']['usd']
          };
          _isLoading = false;
          _isOffline = false;  // Ensure this is set to false when we successfully fetch rates
        });
        _saveExchangeRates();
      } else {
        throw Exception('Failed to load exchange rates');
      }
    } catch (e) {
      print('Error fetching rates: $e');
      setState(() {
        _isOffline = true;  // Set to true if there's an error fetching rates
      });
    }
  }

  Future<void> _saveExchangeRates() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('exchangeRates', json.encode(_exchangeRates));
    await prefs.setInt('lastFetchTime', DateTime.now().millisecondsSinceEpoch);
  }

  Future<void> _handleOfflineRates() async {
    final prefs = await SharedPreferences.getInstance();
    final storedRates = prefs.getString('exchangeRates');
    final lastFetchTime = prefs.getInt('lastFetchTime');

    if (storedRates != null && lastFetchTime != null) {
      final rates = json.decode(storedRates) as Map<String, dynamic>;
      final fetchTime = DateTime.fromMillisecondsSinceEpoch(lastFetchTime);
      final hoursSinceLastFetch = DateTime.now().difference(fetchTime).inHours;

      if (hoursSinceLastFetch < 24) {
        setState(() {
          _exchangeRates = rates.map((key, value) => MapEntry(key, value.toDouble()));
          _isLoading = false;
          // Only set _isOffline to true if we haven't successfully fetched rates
          _isOffline = _isOffline || true;
        });
        return;
      }
    }

    setState(() {
      _exchangeRates = _fallbackRates;
      _isLoading = false;
      // Only set _isOffline to true if we haven't successfully fetched rates
      _isOffline = _isOffline || true;
    });
  }

  void _convertCurrency(bool isFromCurrency) {
    if (isFromCurrency) {
      if (_amountController.text.isNotEmpty) {
        double amount = double.parse(_amountController.text);
        double result = _convert(amount, _fromCurrency, _toCurrency);
        _convertedController.text = result.toStringAsFixed(2);
      } else {
        _convertedController.clear();
      }
    } else {
      if (_convertedController.text.isNotEmpty) {
        double converted = double.parse(_convertedController.text);
        double result = _convert(converted, _toCurrency, _fromCurrency);
        _amountController.text = result.toStringAsFixed(2);
      } else {
        _amountController.clear();
      }
    }
    _updateWidget();
  }

  void _updateCurrencyAndConvert(String? newCurrency, bool isFromCurrency) {
    if (newCurrency != null) {
      setState(() {
        if (isFromCurrency) {
          if (_fromCurrency != newCurrency) {
            double amount = double.tryParse(_amountController.text) ?? 0;
            double newAmount = _convert(amount, _fromCurrency, newCurrency);
            _amountController.text = newAmount.toStringAsFixed(2);
            _fromCurrency = newCurrency;
          }
        } else {
          if (_toCurrency != newCurrency) {
            double amount = double.tryParse(_convertedController.text) ?? 0;
            double newAmount = _convert(amount, _toCurrency, newCurrency);
            _convertedController.text = newAmount.toStringAsFixed(2);
            _toCurrency = newCurrency;
          }
        }
      });
    }
    _updateWidget();
  }

  double _convert(double value, String from, String to) {
    if (!_exchangeRates.containsKey(from) || !_exchangeRates.containsKey(to)) return 0;
    final eurValue = value / _exchangeRates[from]!;
    return eurValue * _exchangeRates[to]!;
  }

  void _swapCurrencies() {
    setState(() {
      String temp = _fromCurrency;
      _fromCurrency = _toCurrency;
      _toCurrency = temp;
      String tempAmount = _amountController.text;
      _amountController.text = _convertedController.text;
      _convertedController.text = tempAmount;
    });
    _updateWidget();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Card(
            elevation: 4,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            color: Colors.white,
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: _isLoading
                  ? const CircularProgressIndicator()
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'Converter',
                          style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                        ),
                        if (_isOffline)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8.0),
                            child: Text(
                              'Offline. Using ${_exchangeRates == _fallbackRates ? 'fallback' : 'stored'} rates.',
                              style: TextStyle(color: Colors.red),
                            ),
                          ),
                        const SizedBox(height: 24),
                        _buildCurrencyInput(
                          _amountController,
                          'Amount',
                          _fromCurrency,
                          (value) => _updateCurrencyAndConvert(value, true),
                          onChanged: (_) => _convertCurrency(true),
                        ),
                        const SizedBox(height: 16),
                        _buildSwapButton(),
                        const SizedBox(height: 16),
                        _buildCurrencyInput(
                          _convertedController,
                          'Converted',
                          _toCurrency,
                          (value) => _updateCurrencyAndConvert(value, false),
                          onChanged: (_) => _convertCurrency(false),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCurrencyInput(
    TextEditingController controller,
    String label,
    String currency,
    void Function(String?) onCurrencyChanged, {
    required void Function(String) onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 14, color: Colors.grey[600]),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              flex: 7,
              child: TextField(
                controller: controller,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}'))],
                decoration: InputDecoration(
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: Colors.grey[300]!),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: Colors.grey[300]!),
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                ),
                onChanged: onChanged,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 3,
              child: DropdownButtonFormField<String>(
                value: currency,
                items: _currencies.map((String value) {
                  return DropdownMenuItem<String>(
                    value: value,
                    child: Text(value),
                  );
                }).toList(),
                onChanged: onCurrencyChanged,
                decoration: InputDecoration(
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: Colors.grey[300]!),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: Colors.grey[300]!),
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSwapButton() {
    return ElevatedButton.icon(
      onPressed: _swapCurrencies,
      icon: const Icon(Icons.swap_vert),
      label: const Text('Swap'),
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      ),
    );
  }
}