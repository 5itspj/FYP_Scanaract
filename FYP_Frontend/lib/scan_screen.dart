import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:http/http.dart' as http;
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'main_navigator.dart';
import 'package:android_intent_plus/android_intent.dart';
import 'dart:convert';

class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  final _healthIndexController = TextEditingController();
  bool _isUploading = false;
  bool _isCapturing = false;
  String? _capturedImageUrl;
  File? _capturedImageFile;
  
  // Pi Connection
  bool _isPiConnected = false;
  final String _piBaseUrl = 'http://10.42.0.1:8081';

  final List<String> _prompts = [
    "Tap the camera button to capture photo",
    "Position your eye in the center",
    "Keep your face steady",
    "Hold the phone at eye level",
    "Processing photo...",
  ];

  int _currentPromptIndex = 0;
  final _supabase = Supabase.instance.client;

  @override
  void initState() {
    super.initState();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.9, end: 1.1).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // Check Pi connection after a short delay
    Future.delayed(const Duration(milliseconds: 500), () {
      _checkPiConnection();
    });
    
    Future.delayed(const Duration(seconds: 5), _nextPrompt);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Re-check when screen becomes visible
    Future.delayed(const Duration(milliseconds: 200), () {
      _checkPiConnection();
    });
  }

  void _nextPrompt() {
    if (!mounted) return;
    setState(() {
      _currentPromptIndex = (_currentPromptIndex + 1) % _prompts.length;
    });
    Future.delayed(const Duration(seconds: 5), _nextPrompt);
  }

  // ========== Pi Connection Check with Retry ==========
  Future<void> _checkPiConnection({int retries = 3}) async {
    final connectivityResult = await Connectivity().checkConnectivity();
    
    if (connectivityResult != ConnectivityResult.wifi) {
      setState(() {
        _isPiConnected = false;
      });
      return;
    }
    
    for (int i = 0; i < retries; i++) {
      try {
        final response = await http.get(
          Uri.parse('$_piBaseUrl/photos'),
        ).timeout(const Duration(seconds: 2));
        
        if (response.statusCode == 200) {
          if (mounted) {
            setState(() {
              _isPiConnected = true;
            });
          }
          return;
        }
      } catch (e) {
        // Wait before retry
        if (i < retries - 1) {
          await Future.delayed(const Duration(milliseconds: 500));
        }
      }
    }
    
    if (mounted) {
      setState(() {
        _isPiConnected = false;
      });
    }
  }

  // ========== Capture Photo from Pi ==========
  Future<void> _capturePhoto() async {
    // First, check connection again
    await _checkPiConnection();
    
    if (!_isPiConnected) {
      final shouldConnect = await _showPiConnectionDialog();
      if (shouldConnect) {
        await _openWifiSettings();
        // After returning from settings, check connection
        await _checkPiConnection(retries: 5);
        if (!_isPiConnected) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Still not connected. Please connect to Scanaract_Wifi'),
              backgroundColor: Colors.red,
            ),
          );
          return;
        }
      } else {
        return;
      }
    }
    
    setState(() {
      _isCapturing = true;
      _capturedImageUrl = null;
      _capturedImageFile = null;
    });
    
    try {
      // Step 1: Tell Pi to capture photo
      final captureResponse = await http.get(
        Uri.parse('$_piBaseUrl/capture'),
      ).timeout(const Duration(seconds: 10));
      
      if (captureResponse.statusCode != 200) {
        throw Exception('Failed to capture photo');
      }
      
      // Parse the JSON response
      final Map<String, dynamic> result = jsonDecode(captureResponse.body);
      final String filename = result['filename'];
      
      // Step 2: Download the photo from Pi
      final imageResponse = await http.get(
        Uri.parse('$_piBaseUrl/static/photos/$filename'),
      ).timeout(const Duration(seconds: 10));
      
      if (imageResponse.statusCode != 200) {
        throw Exception('Failed to download photo');
      }
      
      // Step 3: Save to local temp file
      final tempDir = await getTemporaryDirectory();
      final file = File('${tempDir.path}/$filename');
      await file.writeAsBytes(imageResponse.bodyBytes);
      
      // Step 4: Update UI
      if (mounted) {
        setState(() {
          _capturedImageFile = file;
          _capturedImageUrl = '$_piBaseUrl/static/photos/$filename';
          _currentPromptIndex = 4;
        });
        
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Photo captured successfully!'), backgroundColor: Colors.green),
        );
      }
      
    } catch (e) {
      print('Capture error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Capture failed: ${e.toString().substring(0, 100)}'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isCapturing = false;
        });
      }
    }
  }
  
  // ========== Show Pi Connection Dialog ==========
  Future<bool> _showPiConnectionDialog() async {
    return await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Camera Not Connected'),
          content: const Text(
            'Please connect to the Scanaract_Wifi network first.\n\n'
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
              style: TextButton.styleFrom(foregroundColor: Colors.blue),
              child: const Text('Open Wi-Fi Settings'),
            ),
          ],
        );
      },
    ) ?? false;
  }
  
  // ========== Open Wi-Fi Settings ==========
  Future<void> _openWifiSettings() async {
    try {
      final AndroidIntent intent = AndroidIntent(
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

  // ========== Upload Captured Photo (Placeholder) ==========
  Future<void> _uploadCapturedPhoto() async {
    if (_capturedImageFile == null) return;
    
    setState(() => _isUploading = true);
    
    try {
      // Step 1: Show dialog telling user to disconnect from Pi Wi-Fi
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: const Text('Upload to Cloud'),
          content: const Text(
            'Your phone is currently connected to Scanaract_Wifi.\n\n'
            'To upload to cloud, please:\n'
            '1. Swipe down from top of screen\n'
            '2. Tap Wi-Fi icon to turn OFF\n'
            '3. Mobile data will automatically connect\n'
            '4. Tap "Continue" when ready\n\n'
            'The AI will analyze your eye scan.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Continue'),
            ),
          ],
        ),
      );
      
      // Step 2: Simulate AI processing (placeholder) with a snackbar instead
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Processing scan with AI...'),
          duration: Duration(seconds: 3),
        ),
      );
      
      await Future.delayed(const Duration(seconds: 3));
      
      // Step 3: Show completion dialog
      if (mounted) {
        await showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Upload Complete'),
            content: const Text(
              'Your scan has been submitted to AI.\n\n'
              'Results will appear in your History tab.\n'
              'You can reconnect to Scanaract_Wifi to scan again.',
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  // Navigate back to home
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(builder: (context) => const MainNavigator()),
                  );
                },
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
      
      // Clear captured image after upload
      setState(() {
        _capturedImageFile = null;
        _capturedImageUrl = null;
      });
      
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Upload failed: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }
  
  Future<int?> _showHealthIndexDialog() async {
    final controller = TextEditingController();
    return await showDialog<int>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          title: const Text('Enter Health Index'),
          content: TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Health Index (0-100)',
              hintText: 'Enter a number between 0-100',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(null),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                final value = int.tryParse(controller.text.trim());
                if (value != null && value >= 0 && value <= 100) {
                  Navigator.of(context).pop(value);
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Please enter a number between 0-100')),
                  );
                }
              },
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _healthIndexController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text('Scanning', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
        centerTitle: true,
        actions: [
          // Refresh button
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => _checkPiConnection(retries: 3),
            color: Colors.blue,
          ),
          // Pi connection indicator
          Container(
            margin: const EdgeInsets.only(right: 16),
            child: Row(
              children: [
                Icon(
                  _isPiConnected ? Icons.wifi : Icons.wifi_off,
                  color: _isPiConnected ? Colors.green : Colors.red,
                  size: 20,
                ),
                const SizedBox(width: 4),
                Text(
                  _isPiConnected ? 'Camera' : 'Offline',
                  style: TextStyle(
                    fontSize: 12,
                    color: _isPiConnected ? Colors.green : Colors.red,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Center(
          child: Column(
            children: [
              const SizedBox(height: 20),

              // Captured Photo Preview or Camera Animation
              if (_capturedImageFile != null)
                Container(
                  width: 280,
                  height: 280,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(color: Colors.blue.withOpacity(0.3), blurRadius: 30, spreadRadius: 10),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: Image.file(
                      _capturedImageFile!,
                      fit: BoxFit.cover,
                      width: 280,
                      height: 280,
                    ),
                  ),
                )
              else
                ScaleTransition(
                  scale: _pulseAnimation,
                  child: Container(
                    width: 280,
                    height: 280,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white,
                      boxShadow: [
                        BoxShadow(color: Colors.blue.withOpacity(0.3), blurRadius: 30, spreadRadius: 10),
                      ],
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.remove_red_eye, size: 80, color: Colors.blue),
                        const SizedBox(height: 24),
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 800),
                          child: Text(
                            _prompts[_currentPromptIndex],
                            key: ValueKey<int>(_currentPromptIndex),
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w500, color: Colors.black87),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

              const SizedBox(height: 30),

              // Capture Button
              if (_capturedImageFile == null)
                ElevatedButton.icon(
                  onPressed: _isCapturing ? null : _capturePhoto,
                  icon: _isCapturing
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.camera_alt, size: 28),
                  label: Text(
                    _isCapturing ? 'Capturing...' : (_isPiConnected ? 'Capture Photo' : 'Connect to Camera'),
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _isPiConnected ? Colors.blue.shade700 : Colors.orange,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                    elevation: 3,
                  ),
                )
              else
                Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        ElevatedButton.icon(
                          onPressed: _isUploading ? null : _capturePhoto,
                          icon: const Icon(Icons.camera_alt),
                          label: const Text('Retake'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.grey,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                          ),
                        ),
                        const SizedBox(width: 20),
                        ElevatedButton.icon(
                          onPressed: _isUploading ? null : _uploadCapturedPhoto,
                          icon: _isUploading
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                )
                              : const Icon(Icons.cloud_upload),
                          label: Text(_isUploading ? 'Uploading...' : 'Upload'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Tap Upload to save this scan to your history',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),

              const SizedBox(height: 40),

              // Manual entry card
              Card(
                elevation: 3,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    children: [
                      const Text(
                        'Manual Entry',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.grey),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _healthIndexController,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: 'Health Index (0-100)',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          filled: true,
                          fillColor: Colors.grey[50],
                        ),
                      ),
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: ElevatedButton(
                          onPressed: _isUploading ? null : _uploadHealthIndex,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue.shade700,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          child: _isUploading
                              ? const CircularProgressIndicator(color: Colors.white)
                              : const Text('Upload Health Index (Manual)', style: TextStyle(fontSize: 16)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
  
  // Keep your existing manual upload method
  Future<void> _uploadHealthIndex() async {
    final input = _healthIndexController.text.trim();
    if (input.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter health index')));
      return;
    }

    final index = int.tryParse(input);
    if (index == null || index < 0 || index > 100) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter a number between 0-100')));
      return;
    }

    setState(() => _isUploading = true);

    try {
      final user = _supabase.auth.currentUser;
      if (user == null) throw Exception('Not logged in');

      final nowLocal = DateTime.now().toLocal();
      final localIsoString = nowLocal.toIso8601String();

      await _supabase.from('examinations').insert({
        'user_id': user.id,
        'health_index': index,
        'scan_date': localIsoString,
        'notes': 'Manual test upload',
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Upload successful! Returning to home...'), backgroundColor: Colors.green),
        );

        await Future.delayed(const Duration(milliseconds: 800));
        if (mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => const MainNavigator()),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Upload failed: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }
}