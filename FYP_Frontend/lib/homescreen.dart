import 'package:flutter/material.dart';
import 'package:android_intent_plus/android_intent.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:http/http.dart' as http;
import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
class HomeScreenState extends State<HomeScreen> {
  final _supabase = Supabase.instance.client;

  Map<String, dynamic>? _profile;
  bool _isProfileLoaded = false;

  List<int> healthScores = [];
  List<String> chartLabels = [];

  List<Map<String, dynamic>> recentExaminations = [];

  bool _showAnimation = false;
  bool _isDeviceConnected = false;
  bool _isConnecting = false;
  final String _piBaseUrl = 'http://10.42.0.1:8081';
  
  final List<Map<String, dynamic>> recentRecords = [
    {'date': '09-24 08:30', 'rating': 82},
    {'date': '09-23 08:30', 'rating': 80},
    {'date': '09-22 08:30', 'rating': 78},
    {'date': '09-21 08:30', 'rating': 70},
  ];

  final List<double> healthScores = [50, 55, 68, 72, 65, 78, 82];
  final List<String> chartLabels = ['9.24', '9.25', '9.26', '9.27', '9.28', '9.29', '9.30'];
  bool _isMatching = false;

  @override
  void initState() {
    super.initState();
    _loadUserProfile();
    _loadRecentExaminations();
    _loadRecentRecords();

    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) setState(() => _showAnimation = true);
    });
  }

  Future<void> _loadUserProfile() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) {
        if (mounted) setState(() => _isProfileLoaded = true);
        return;
      }

      final data = await _supabase
          .from('profiles')
          .select()
          .eq('id', user.id)
          .single();

      if (mounted) {
        setState(() {
          _profile = data;
          _isProfileLoaded = true;
        });
      }
    } catch (e) {
      debugPrint('Failed to load profile: $e');
      if (mounted) setState(() => _isProfileLoaded = true);
    }
  }

  Future<void> _loadRecentExaminations() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return;

      final data = await _supabase
          .from('examinations')
          .select('health_index, scan_date')
          .eq('user_id', user.id)
          .order('scan_date', ascending: false)
          .limit(7);

      if (mounted) {
        setState(() {
          healthScores = data.map<int>((e) => e['health_index'] as int).toList().reversed.toList();
          chartLabels = data.map<String>((e) {
            final date = DateTime.parse(e['scan_date'] as String).toLocal();
            return DateFormat('M.d').format(date);
          }).toList().reversed.toList();
        });
      }
    } catch (e) {
      debugPrint('Failed to load chart data: $e');
      if (mounted) {
        setState(() {
          _showAnimation = true;
        });
      }
    });
    
    // Check if already connected to Pi when app loads
    _checkPiConnection();
  }

  /// Check if currently on Pi network and Pi is reachable
  Future<void> _checkPiConnection() async {
    final connectivityResult = await Connectivity().checkConnectivity();
    
    if (connectivityResult == ConnectivityResult.wifi) {
      try {
        final response = await http.get(Uri.parse('$_piBaseUrl/photos')).timeout(
          const Duration(seconds: 3),
          onTimeout: () => throw Exception('Timeout'),
        );
        if (response.statusCode == 200) {
          setState(() {
            _isDeviceConnected = true;
          });
          return;
        }
      } catch (e) {
        // Pi not reachable
      }
    }
    
    setState(() {
      _isDeviceConnected = false;
    });
  }

  /// Opens system Wi-Fi settings
  Future<void> _openWifiSettings() async {
    try {
      const AndroidIntent intent = AndroidIntent(
        action: 'android.settings.WIFI_SETTINGS',
      );
      await intent.launch();
    } catch (e) {
          healthScores = [50, 55, 68, 72, 65, 78, 82];
          chartLabels = ['4.5', '4.6', '4.7', '4.8', '4.9', '4.10', '4.11'];
        });
      }
    }
  }

  Future<void> _loadRecentRecords() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return;

      final data = await _supabase
          .from('examinations')
          .select('health_index, scan_date')
          .eq('user_id', user.id)
          .order('scan_date', ascending: false)
          .limit(4);

      if (mounted) {
        setState(() {
          recentExaminations = data.map((e) {
            final date = DateTime.parse(e['scan_date'] as String).toLocal();
            return {
              'date': DateFormat('MM.dd HH:mm').format(date),
              'rating': e['health_index'],
            };
          }).toList();
        });
      }
    } catch (e) {
      debugPrint('Failed to load recent records: $e');
    }
  }

  void refreshProfile() {
    _loadUserProfile();
    _loadRecentExaminations();
    _loadRecentRecords();
  }

  String get userName => _profile?['full_name'] ?? 'User';
  int get healthIndex => _profile?['health_index'] ?? 70;

  void _startMatching() {
    if (_isMatching || _isDeviceConnected) return;

    setState(() => _isMatching = true);

    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open Wi-Fi settings')),
        );
      }
    }
  }

  /// Shows dialog asking user to connect to Pi Wi-Fi
  Future<void> _showConnectionDialog() async {
    final shouldOpenSettings = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Connect to Camera'),
          content: const Text(
            'Please connect to the Scanaract_Wifi network to use the camera.\n\n'
            'Network: Scanaract_Wifi\n'
            'Password: scanaractpi',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: TextButton.styleFrom(
                foregroundColor: Colors.blue,
              ),
              child: const Text('Open Wi-Fi Settings'),
            ),
          ],
        );
      },
    );

    if (shouldOpenSettings == true) {
      await _openWifiSettings();
    }
  }

  /// Start connection process - shows dialog to connect to Pi
  Future<void> _startConnection() async {
    if (_isDeviceConnected || _isConnecting) return;
    
    // First check if already on Pi network
    await _checkPiConnection();
    
    if (_isDeviceConnected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Already connected to camera!'),
          backgroundColor: Colors.green,
        ),
      );
      return;
    }
    
    // Show dialog to guide user to connect
    await _showConnectionDialog();
    
    // After returning from settings, check connection again
    setState(() {
      _isConnecting = true;
    });
    
    // Poll for connection (user might have connected)
    await _waitForConnection();
  }
  
  /// Poll Pi to check if user connected to the network
  Future<void> _waitForConnection() async {
    int attempts = 0;
    const maxAttempts = 20; // 20 seconds total
    
    while (attempts < maxAttempts && mounted) {
      await Future.delayed(const Duration(seconds: 1));
      
      final connectivityResult = await Connectivity().checkConnectivity();
      if (connectivityResult == ConnectivityResult.wifi) {
        try {
          final response = await http.get(Uri.parse('$_piBaseUrl/photos')).timeout(
            const Duration(seconds: 2),
            onTimeout: () => throw Exception('Timeout'),
          );
          if (response.statusCode == 200) {
            if (mounted) {
              setState(() {
                _isDeviceConnected = true;
                _isConnecting = false;
              });
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Camera connected successfully!'),
                  backgroundColor: Colors.green,
                ),
              );
            }
            return;
          }
        } catch (e) {
          // Still not connected
        }
      }
      attempts++;
    }
    
    if (mounted) {
      setState(() {
        _isConnecting = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not connect to camera. Please check Wi-Fi settings.'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isProfileLoaded) {
      return Scaffold(
        backgroundColor: Colors.blue[50],
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: Colors.blue[50],
      body: SafeArea(
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(24, 32, 24, 60),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.blue.shade700, Colors.blue.shade500],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(32)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Hi, $userName',
                        style: const TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Today Health Index: $healthIndex',
                        style: const TextStyle(
                          fontSize: 16,
                          color: Colors.white70,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                  CircleAvatar(
                    radius: 32,
                    backgroundColor: Colors.white,
                    child: ClipOval(
                      child: Image.network(
                        _profile?['avatar_url'] ?? 'https://randomuser.me/api/portraits/women/44.jpg',
                        fit: BoxFit.cover,
                        width: 64,
                        height: 64,
                        errorBuilder: (_, __, ___) => const Icon(Icons.person, size: 40, color: Colors.grey),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0.0, end: 1.0),
                      duration: const Duration(milliseconds: 600),
                      curve: Curves.easeOut,
                      builder: (context, value, child) {
                        return Transform.translate(
                          offset: Offset(0, (1 - value) * 30),
                          child: Opacity(opacity: value, child: child),
                        );
                      },
                      child: InkWell(
                        onTap: _isDeviceConnected ? null : _startConnection,
                        borderRadius: BorderRadius.circular(16),
                        child: Card(
                          elevation: 3,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Row(
                              children: [
                                if (_isConnecting)
                                  SizedBox(
                                if (_isMatching)
                                  const SizedBox(
                                    width: 48,
                                    height: 48,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 3,
                                      valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
                                    ),
                                  )
                                else
                                  Icon(
                                    _isDeviceConnected ? Icons.check_circle : Icons.wifi,
                                    color: _isDeviceConnected ? Colors.green : Colors.blue,
                                    size: 48,
                                  ),
                                const SizedBox(width: 20),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'Camera Status',
                                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                                      ),
                                      const Text('Device status', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                                      const SizedBox(height: 4),
                                      Text(
                                        _isConnecting
                                            ? 'Connecting...'
                                            : (_isDeviceConnected 
                                                ? 'Connected to Scanaract_Wifi' 
                                                : 'Not Connected'),
                                        _isMatching ? 'Matching...' : (_isDeviceConnected ? 'Connected' : 'Disconnected'),
                                        style: TextStyle(
                                          fontSize: 16,
                                          color: _isConnecting
                                              ? Colors.blue
                                              : (_isDeviceConnected ? Colors.green : Colors.orange),
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      if (!_isDeviceConnected && !_isConnecting)
                                        const Padding(
                                          padding: EdgeInsets.only(top: 4),
                                          child: Text(
                                            'Tap to connect to camera',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: Colors.grey,
                                              fontStyle: FontStyle.italic,
                                            ),
                                            'Tap to start matching',
                                            style: TextStyle(fontSize: 12, color: Colors.grey, fontStyle: FontStyle.italic),
                                          ),
                                        ),
                                      if (_isDeviceConnected && !_isConnecting)
                                        const Padding(
                                          padding: EdgeInsets.only(top: 4),
                                          child: Text(
                                            'Ready to scan!',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: Colors.green,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 24),

                    Card(
                      elevation: 3,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Health trend chart (last 7 records)',
                              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 16),
                            SizedBox(
                              height: 220,
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: List.generate(
                                  healthScores.length,
                                  (index) {
                                    double targetHeight = healthScores[index] * 1.8;
                                    return Column(
                                      mainAxisAlignment: MainAxisAlignment.end,
                                      children: [
                                        AnimatedContainer(
                                          duration: const Duration(milliseconds: 800),
                                          curve: Curves.easeOut,
                                          width: 35,
                                          height: _showAnimation ? targetHeight : 0,
                                          decoration: BoxDecoration(
                                            color: Colors.blue.shade400,
                                            borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
                                            boxShadow: _showAnimation
                                                ? [BoxShadow(color: Colors.blue.withOpacity(0.4), blurRadius: 8, offset: const Offset(0, 4))]
                                                : null,
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        Text(
                                          chartLabels.length > index ? chartLabels[index] : '',
                                          style: const TextStyle(fontSize: 12, color: Colors.grey),
                                        ),
                                      ],
                                    );
                                  },
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 24),

                    Card(
                      elevation: 3,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Recent detection records',
                              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 16),
                            if (recentExaminations.isEmpty)
                              const Padding(
                                padding: EdgeInsets.all(40),
                                child: Center(child: Text('No records yet', style: TextStyle(color: Colors.grey))),
                              )
                            else
                              ...recentExaminations.map((record) => Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 12),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          record['date'] ?? '',
                                          style: const TextStyle(fontSize: 16, color: Colors.black87),
                                        ),
                                        Text(
                                          'Score: ${record['rating']}',
                                          style: TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.blue.shade800,
                                          ),
                                        ),
                                      ],
                                    ),
                                  )),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}