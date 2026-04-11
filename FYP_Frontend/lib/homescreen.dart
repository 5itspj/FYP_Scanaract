import 'package:flutter/material.dart';
import 'package:android_intent_plus/android_intent.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:http/http.dart' as http;
import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // ========== UI Animation ==========
  bool _showAnimation = false;
  
  // ========== Supabase Data ==========
  final SupabaseClient _supabase = Supabase.instance.client;
  Map<String, dynamic>? _profile;
  bool _isProfileLoaded = false;
  List<Map<String, dynamic>> recentExaminations = [];
  
  // ========== Pi Connection ==========
  bool _isDeviceConnected = false;
  bool _isConnecting = false;
  final String _piBaseUrl = 'http://10.42.0.1:8081';
  
  // ========== Chart Data ==========
  final List<double> healthScores = [50, 55, 68, 72, 65, 78, 82];
  final List<String> chartLabels = ['9.24', '9.25', '9.26', '9.27', '9.28', '9.29', '9.30'];

  // ========== Getters ==========
  String get userName => _profile?['full_name'] ?? 'User';
  int get healthIndex => _profile?['health_index'] ?? 70;

  @override
  void initState() {
    super.initState();
    
    // UI animation
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) {
        setState(() {
          _showAnimation = true;
        });
      }
    });
    
    // Load Supabase data
    _loadUserProfile();
    _loadRecentExaminations();
    
    // Check Pi connection
    _checkPiConnection();
  }

  // ========== Supabase Methods ==========
  Future<void> _loadUserProfile() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user != null) {
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
      } else {
        if (mounted) {
          setState(() {
            _isProfileLoaded = true;
          });
        }
      }
    } catch (e) {
      debugPrint('Error loading profile: $e');
      if (mounted) {
        setState(() {
          _isProfileLoaded = true;
        });
      }
    }
  }

  Future<void> _loadRecentExaminations() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user != null) {
        final data = await _supabase
            .from('examinations')
            .select()
            .eq('user_id', user.id)
            .order('created_at', ascending: false)
            .limit(4);
        if (mounted) {
          setState(() {
            recentExaminations = data.map((e) => {
              'date': e['created_at']?.toString().substring(5, 16) ?? 'Unknown',
              'rating': e['health_score'] ?? 0,
            }).toList();
          });
        }
      }
    } catch (e) {
      debugPrint('Error loading examinations: $e');
    }
  }

  // ========== Pi Connection Methods ==========
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

  Future<void> _openWifiSettings() async {
    try {
      const AndroidIntent intent = AndroidIntent(
        action: 'android.settings.WIFI_SETTINGS',
      );
      await intent.launch();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open Wi-Fi settings')),
        );
      }
    }
  }

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

  Future<void> _startConnection() async {
    if (_isDeviceConnected || _isConnecting) return;
    
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
    
    await _showConnectionDialog();
    
    setState(() {
      _isConnecting = true;
    });
    
    await _waitForConnection();
  }
  
  Future<void> _waitForConnection() async {
    int attempts = 0;
    const maxAttempts = 20;
    
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
    // Show loading while profile loads
    if (!_isProfileLoaded) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: Colors.blue.shade50,
      body: SafeArea(
        child: Column(
          children: [
            // Header with gradient
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
                      Text(
                        'Health Index: $healthIndex',
                        style: const TextStyle(
                          fontSize: 16,
                          color: Colors.white70,
                        ),
                      ),
                    ],
                  ),
                  CircleAvatar(
                    radius: 32,
                    backgroundColor: Colors.white,
                    child: ClipOval(
                      child: _profile?['avatar_url'] != null
                          ? Image.network(
                              _profile!['avatar_url'],
                              fit: BoxFit.cover,
                              width: 64,
                              height: 64,
                              errorBuilder: (c, e, s) => const Icon(Icons.person, size: 40),
                            )
                          : const Icon(Icons.person, size: 40, color: Colors.blue),
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
                    // Pi Connection Card
                    TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0.0, end: 1.0),
                      duration: const Duration(milliseconds: 600),
                      curve: Curves.easeOut,
                      builder: (context, value, child) {
                        return Transform.translate(
                          offset: Offset(0, (1 - value) * 30),
                          child: Opacity(
                            opacity: value,
                            child: child,
                          ),
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
                                      const SizedBox(height: 4),
                                      Text(
                                        _isConnecting
                                            ? 'Connecting...'
                                            : (_isDeviceConnected 
                                                ? 'Connected to Scanaract_Wifi' 
                                                : 'Not Connected'),
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

                    // Health Trend Chart
                    Card(
                      elevation: 3,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Health trend chart (last 7 days)',
                              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 16),
                            SizedBox(
                              height: 220,
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: List.generate(healthScores.length, (index) {
                                  double targetHeight = healthScores[index] * 1.8;
                                  return Column(
                                    mainAxisAlignment: MainAxisAlignment.end,
                                    children: [
                                      AnimatedContainer(
                                        duration: const Duration(milliseconds: 1200),
                                        curve: Curves.easeOut,
                                        width: 35,
                                        height: _showAnimation ? targetHeight : 0,
                                        decoration: BoxDecoration(
                                          color: Colors.blue.shade400,
                                          borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
                                          boxShadow: _showAnimation
                                              ? [
                                                  BoxShadow(
                                                    color: Colors.blue.withOpacity(0.4),
                                                    blurRadius: 8,
                                                    offset: const Offset(0, 4),
                                                  )
                                                ]
                                              : null,
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        chartLabels[index],
                                        style: const TextStyle(fontSize: 12, color: Colors.grey),
                                      ),
                                    ],
                                  );
                                }),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 24),

                    // Recent Records
                    TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0.0, end: 1.0),
                      duration: const Duration(milliseconds: 800),
                      curve: Curves.easeOut,
                      builder: (context, value, child) {
                        return Transform.translate(
                          offset: Offset(0, (1 - value) * 30),
                          child: Opacity(
                            opacity: value,
                            child: child,
                          ),
                        );
                      },
                      child: Card(
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
                                  padding: EdgeInsets.all(20),
                                  child: Text(
                                    'No recent examinations',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(color: Colors.grey),
                                  ),
                                )
                              else
                                ...recentExaminations.map((record) => Padding(
                                      padding: const EdgeInsets.symmetric(vertical: 10),
                                      child: Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text(
                                            record['date'],
                                            style: const TextStyle(fontSize: 16, color: Colors.black87),
                                          ),
                                          Text(
                                            'Rating: ${record['rating']}',
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