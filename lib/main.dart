import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'dart:io';
import 'dart:async'; // Add this import
import 'package:flutter/foundation.dart' show kIsWeb;

// Add these color definitions at the top of the file, outside any class
const Color primaryColor = Color(0xFF6B4E71);  // A muted purple
const Color accentColor = Color(0xFFE6A4B4);   // A soft pink
const Color textColor = Color(0xFF333333);     // Dark gray for text
const Color backgroundColor = Color(0xFFF5E6E8);  // Light pink background

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
  ));
  runApp(const CurrencyConverterApp());
}

class CurrencyConverterApp extends StatelessWidget {
  const CurrencyConverterApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Currency Converter',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: primaryColor,
          primary: primaryColor,
          secondary: accentColor,
          background: Colors.transparent,
        ),
        scaffoldBackgroundColor: Colors.transparent,
        fontFamily: 'Roboto',
        textTheme: TextTheme(
          titleLarge: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: textColor),
          bodyMedium: TextStyle(fontSize: 14, color: textColor),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: primaryColor,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            elevation: 0,
          ),
        ),
      ),
      home: const BackgroundWrapper(child: CurrencyConverterScreen()),
    );
  }
}

class BackgroundWrapper extends StatelessWidget {
  final Widget child;

  const BackgroundWrapper({Key? key, required this.child}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        image: DecorationImage(
          image: AssetImage('assets/background.png'),
          fit: BoxFit.cover,
        ),
      ),
      child: child,
    );
  }
}

class CurrencyConverterScreen extends StatefulWidget {
  const CurrencyConverterScreen({super.key});

  @override
  _CurrencyConverterScreenState createState() => _CurrencyConverterScreenState();
}

class _CurrencyConverterScreenState extends State<CurrencyConverterScreen> with SingleTickerProviderStateMixin {
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

  late Stream<ConnectivityResult> _connectivityStream;

  // Add these new properties
  late String _defaultFromCurrency;
  late String _defaultToCurrency;

  late AnimationController _animationController;
  late Animation<double> _swapAnimation;

  Timer? _connectivityTimer;

  @override
  void initState() {
    super.initState();
    print("initState called");
    _amountController.text = '1.00';
    _connectivityStream = Connectivity().checkConnectivity().asStream();
    _setupConnectivityListener();
    _loadDefaultCurrencies();
    _loadExchangeRates();
    _checkOnlineStatus();
    _startPeriodicConnectivityCheck();

    _animationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    _swapAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );
    print("initState completed");
  }

  @override
  void dispose() {
    _connectivityTimer?.cancel();
    _animationController.dispose();
    super.dispose();
  }

  // Add this method to load default currencies
  Future<void> _loadDefaultCurrencies() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _defaultFromCurrency = prefs.getString('defaultFromCurrency') ?? 'AED';
      _defaultToCurrency = prefs.getString('defaultToCurrency') ?? 'INR';
      _fromCurrency = _defaultFromCurrency;
      _toCurrency = _defaultToCurrency;
    });
  }

  // Add this method to save default currencies
  Future<void> _saveDefaultCurrencies() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('defaultFromCurrency', _fromCurrency);
    await prefs.setString('defaultToCurrency', _toCurrency);
    setState(() {
      _defaultFromCurrency = _fromCurrency;
      _defaultToCurrency = _toCurrency;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Default currencies saved')),
    );
  }

  void _setupConnectivityListener() {
    _connectivityStream.listen((ConnectivityResult result) {
      _checkOnlineStatus();
    });
  }

  void _startPeriodicConnectivityCheck() {
    _connectivityTimer = Timer.periodic(Duration(seconds: 30), (_) => _checkOnlineStatus());
  }

  Future<void> _checkOnlineStatus() async {
    print("Checking online status");
    try {
      var connectivityResult = await (Connectivity().checkConnectivity());
      if (connectivityResult == ConnectivityResult.none) {
        print("No connectivity");
        setState(() {
          _isOffline = true;
        });
      } else {
        print("Has connectivity, checking internet");
        bool isOnline = await _checkInternetConnection();
        setState(() {
          _isOffline = !isOnline;
        });
        print("Online status: $isOnline");
        if (isOnline) {
          _loadExchangeRates();
        }
      }
    } catch (e) {
      print("Error checking online status: $e");
      setState(() {
        _isOffline = true;
      });
    }
  }

  Future<bool> _checkInternetConnection() async {
    if (kIsWeb) {
      // For web, we'll consider it online if we can load the exchange rates
      try {
        await _fetchExchangeRates();
        return true;
      } catch (e) {
        print("Web connection check failed: $e");
        return false;
      }
    } else {
      // For mobile, we'll use the previous method
      try {
        final response = await http.get(Uri.parse('https://www.google.com'))
            .timeout(Duration(seconds: 5));
        return response.statusCode == 200;
      } catch (e) {
        print("Mobile connection check failed: $e");
        return false;
      }
    }
  }

  Future<void> _loadExchangeRates() async {
    print("Loading exchange rates");
    setState(() {
      _isLoading = true;
    });
    try {
      await _fetchExchangeRates();
    } catch (e) {
      print("Error fetching rates: $e");
      await _handleOfflineRates();
    } finally {
      _convertCurrency(true);
      setState(() {
        _isLoading = false;
      });
    }
    print("Exchange rates loaded");
  }

  Future<void> _fetchExchangeRates() async {
    print("Fetching exchange rates");
    final response = await http.get(Uri.parse(
        'https://cdn.jsdelivr.net/npm/@fawazahmed0/currency-api@latest/v1/currencies/eur.json'))
        .timeout(Duration(seconds: 10));
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
        _isOffline = false;
      });
      _saveExchangeRates();
      print("Exchange rates fetched successfully");
    } else {
      print("Failed to fetch exchange rates: ${response.statusCode}");
      throw Exception('Failed to load exchange rates');
    }
  }

  Future<void> _saveExchangeRates() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('exchangeRates', json.encode(_exchangeRates));
    await prefs.setInt('lastFetchTime', DateTime.now().millisecondsSinceEpoch);
  }

  Future<void> _handleOfflineRates() async {
    print("Handling offline rates");
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
          _isOffline = true;
        });
        print("Using stored rates");
        return;
      }
    }

    setState(() {
      _exchangeRates = Map.from(_fallbackRates);
      _isOffline = true;
    });
    print("Using fallback rates");
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
  }

  double _convert(double value, String from, String to) {
    if (!_exchangeRates.containsKey(from) || !_exchangeRates.containsKey(to)) return 0;
    final eurValue = value / _exchangeRates[from]!;
    return eurValue * _exchangeRates[to]!;
  }

  void _swapCurrencies() {
    _animationController.forward(from: 0).then((_) {
      setState(() {
        String temp = _fromCurrency;
        _fromCurrency = _toCurrency;
        _toCurrency = temp;
        String tempAmount = _amountController.text;
        _amountController.text = _convertedController.text;
        _convertedController.text = tempAmount;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    print("Building UI, isLoading: $_isLoading, isOffline: $_isOffline");
    if (kReleaseMode) {
      getAppVersion().then((version) => print('App Version: $version'));
    }
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: Center(
            child: SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: 400,
                  minHeight: 100,
                ),
                child: Card(
                  elevation: 8,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  color: backgroundColor.withOpacity(0.9),
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: _isLoading || _exchangeRates.isEmpty
                        ? const Center(child: CircularProgressIndicator())
                        : Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _buildHeader(),
                              if (_isOffline) _buildOfflineIndicator(),
                              const SizedBox(height: 24),
                              _buildCurrencyInput(_amountController, 'Amount', _fromCurrency, (value) => _updateCurrencyAndConvert(value, true), true),
                              const SizedBox(height: 16),
                              _buildSwapButton(),
                              const SizedBox(height: 16),
                              _buildCurrencyInput(_convertedController, 'Converted', _toCurrency, (value) => _updateCurrencyAndConvert(value, false), false),
                            ],
                          ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text('Converter', style: Theme.of(context).textTheme.titleLarge),
        Row(
          children: [
            _buildStatusIndicator(),
            SizedBox(width: 12),
            _buildSetDefaultButton(),
          ],
        ),
      ],
    );
  }

  Widget _buildOfflineIndicator() {
    return Padding(
      padding: const EdgeInsets.only(top: 8.0),
      child: Text(
        'Offline. Using ${_exchangeRates == _fallbackRates ? 'fallback' : 'stored'} rates.',
        style: TextStyle(color: Colors.red, fontSize: 12),
      ),
    );
  }

  Widget _buildStatusIndicator() {
    return TweenAnimationBuilder(
      tween: Tween<double>(begin: 0.8, end: 1.2),
      duration: const Duration(seconds: 1),
      builder: (context, double scale, child) {
        return Transform.scale(
          scale: scale,
          child: Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _getStatusColor(),
            ),
          ),
        );
      },
    );
  }

  Widget _buildSetDefaultButton() {
    return ElevatedButton(
      onPressed: _saveDefaultCurrencies,
      child: Text('Set Default', style: TextStyle(fontSize: 12)),
      style: ElevatedButton.styleFrom(
        backgroundColor: accentColor,
        foregroundColor: textColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        elevation: 0,
      ),
    );
  }

  Widget _buildSwapButton() {
    return AnimatedBuilder(
      animation: _swapAnimation,
      builder: (context, child) {
        return Transform.rotate(
          angle: _swapAnimation.value * 3.14159,
          child: ElevatedButton.icon(
            onPressed: _swapCurrencies,
            icon: Icon(Icons.swap_vert, size: 20),
            label: Text('Swap'),
            style: ElevatedButton.styleFrom(
              backgroundColor: primaryColor,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              elevation: 0,
            ),
          ),
        );
      },
    );
  }

  Widget _buildCurrencyInput(
    TextEditingController controller,
    String label,
    String currency,
    void Function(String?) onCurrencyChanged,
    bool isFromCurrency,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 14, color: Colors.grey[600])),
        SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              flex: 7,
              child: _buildAnimatedTextField(controller, isFromCurrency),
            ),
            SizedBox(width: 8),
            Expanded(
              flex: 3,
              child: _buildCurrencyDropdown(currency, onCurrencyChanged),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildAnimatedTextField(TextEditingController controller, bool isFromCurrency) {
    return TweenAnimationBuilder(
      tween: Tween<double>(begin: 0, end: 1),
      duration: Duration(milliseconds: 300),
      builder: (context, double value, child) {
        return Transform.scale(
          scale: value,
          child: TextField(
            controller: controller,
            keyboardType: TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}'))],
            decoration: InputDecoration(
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            ),
            onChanged: (_) => _convertCurrency(isFromCurrency),
          ),
        );
      },
    );
  }

  Widget _buildCurrencyDropdown(String currency, void Function(String?) onChanged) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: primaryColor),
        borderRadius: BorderRadius.circular(12),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: currency,
          items: _currencies.map((String value) {
            return DropdownMenuItem<String>(
              value: value,
              child: Container(
                alignment: Alignment.center,
                child: Text(
                  value,
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }).toList(),
          onChanged: onChanged,
          icon: Icon(Icons.arrow_drop_down, color: primaryColor),
          iconSize: 24,
          elevation: 16,
          style: TextStyle(color: textColor, fontSize: 14),
          dropdownColor: backgroundColor,
          isExpanded: true, // This ensures the dropdown takes full width
          alignment: AlignmentDirectional.center, // This centers the selected item
        ),
      ),
    );
  }

  Color _getStatusColor() {
    return _isOffline ? Colors.red : Colors.green;
  }
}

Future<String> getAppVersion() async {
  PackageInfo packageInfo = await PackageInfo.fromPlatform();
  return '${packageInfo.version}+${packageInfo.buildNumber}';
}