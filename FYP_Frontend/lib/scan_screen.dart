import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:http/http.dart' as http;
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'main_navigator.dart';
import 'package:android_intent_plus/android_intent.dart';
import 'dart:convert';
import 'package:flutter_mjpeg/flutter_mjpeg.dart';

class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen>
    with SingleTickerProviderStateMixin {
  final String _gradioBaseUrl =
      'https://perram27-cataract-detection-api.hf.space';

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

    Future.delayed(const Duration(milliseconds: 500), () {
      _checkPiConnection();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    Future.delayed(const Duration(milliseconds: 200), () {
      _checkPiConnection();
    });
  }

  // ========== Pi Connection Check ==========
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
        final response = await http
            .get(Uri.parse('$_piBaseUrl/photos'))
            .timeout(const Duration(seconds: 2));

        if (response.statusCode == 200) {
          if (mounted) {
            setState(() {
              _isPiConnected = true;
            });
          }
          return;
        }
      } catch (e) {
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

  // ========== Retake Photo ==========
  void _retakePhoto() {
    setState(() {
      _capturedImageFile = null;
      _capturedImageUrl = null;
    });
  }

  // ========== Capture Photo from Pi ==========
  Future<void> _capturePhoto() async {
    await _checkPiConnection();

    if (!_isPiConnected) {
      final shouldConnect = await _showPiConnectionDialog();
      if (shouldConnect) {
        await _openWifiSettings();
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
    });

    try {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('📸 Capturing... hold still!'),
            duration: Duration(milliseconds: 800),
            backgroundColor: Colors.blue,
          ),
        );
      }

      await Future.delayed(const Duration(milliseconds: 300));

      final captureResponse = await http
          .get(Uri.parse('$_piBaseUrl/capture'))
          .timeout(const Duration(seconds: 10));

      if (captureResponse.statusCode != 200) {
        throw Exception('Failed to capture photo');
      }

      final Map<String, dynamic> result = jsonDecode(captureResponse.body);
      final String filename = result['filename'];

      final imageResponse = await http
          .get(Uri.parse('$_piBaseUrl/static/photos/$filename'))
          .timeout(const Duration(seconds: 10));

      if (imageResponse.statusCode != 200) {
        throw Exception('Failed to download photo');
      }

      final tempDir = await getTemporaryDirectory();
      final file = File('${tempDir.path}/$filename');
      await file.writeAsBytes(imageResponse.bodyBytes);

      if (mounted) {
        setState(() {
          _capturedImageFile = file;
          _capturedImageUrl = '$_piBaseUrl/static/photos/$filename';
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Photo captured! Review below'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      print('Capture error: $e');
      final msg = e.toString();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Capture failed: ${msg.length > 100 ? msg.substring(0, 100) : msg}'),
            backgroundColor: Colors.red,
          ),
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
        ) ??
        false;
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

  // ========== Upload Captured Photo to Cloud AI ==========
  Future<void> _uploadCapturedPhoto() async {
    if (_capturedImageFile == null) {
      // If no image captured yet, just capture one
      await _capturePhoto();
      if (_capturedImageFile == null) return;
    }

    setState(() => _isUploading = true);

    try {
      // First, get the image data BEFORE disconnecting
      final bytes = await _capturedImageFile!.readAsBytes();
      final base64Image = base64Encode(bytes);
      final String dataUri = 'data:image/jpeg;base64,$base64Image';

      // Show dialog telling user to disconnect from Pi Wi-Fi
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: const Text('Upload to Cloud AI'),
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

      // Wait for network to switch to mobile data
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('📡 Connecting to cloud...'),
          duration: Duration(seconds: 2),
        ),
      );
      await Future.delayed(const Duration(seconds: 3));

      // Show processing
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('🤖 AI analyzing your eye scan...'),
          duration: Duration(seconds: 2),
        ),
      );

      // Step 1: Upload to Supabase Storage first (to get public URL)
      final user = _supabase.auth.currentUser;
      if (user == null) throw Exception('Not logged in');

      final fileName = 'scan_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final filePath = 'scans/${user.id}/$fileName';

      // Upload to Supabase Storage
      await _supabase.storage.from('inspection_results').uploadBinary(
            filePath,
            bytes,
            fileOptions: const FileOptions(contentType: 'image/jpeg'),
          );

      // Get public URL
      final imageUrl = _supabase.storage.from('inspection_results').getPublicUrl(filePath);
      print('Image uploaded to: $imageUrl');

      // Step 2: Send to Gradio API
      final postUrl = Uri.parse('$_gradioBaseUrl/gradio_api/call/predict');
      final postResponse = await http
          .post(
            postUrl,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              "data": [
                {
                  "path": imageUrl,
                  "meta": {"_type": "gradio.FileData"},
                },
              ],
            }),
          )
          .timeout(const Duration(seconds: 30));

      if (postResponse.statusCode != 200) {
        throw Exception('Failed to submit prediction: ${postResponse.body}');
      }

      final postResult = jsonDecode(postResponse.body);
      final String? eventId = postResult['event_id'];

      if (eventId == null) {
        throw Exception('Server did not return an event_id.');
      }

      // Step 3: Get results
      final getUrl = Uri.parse('$_gradioBaseUrl/gradio_api/call/predict/$eventId');

      final client = http.Client();
      final request = http.Request('GET', getUrl);
      final streamedResponse = await client
          .send(request)
          .timeout(const Duration(seconds: 60));

      String finalPrediction = 'Unknown';
      String finalDetails = '';
      bool isComplete = false;

      final stream = streamedResponse.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter());

      await for (var line in stream) {
        if (line.startsWith('event: complete')) {
          isComplete = true;
        } else if (isComplete && line.startsWith('data: ')) {
          final dataStr = line.substring(6);
          final List<dynamic> resultData = jsonDecode(dataStr);
          if (resultData.isNotEmpty) {
            finalPrediction = resultData[0]?.toString() ?? 'No prediction';
            if (resultData.length > 1) {
              finalDetails = resultData[1]?.toString() ?? 'No details';
            }
          }
          break;
        } else if (line.startsWith('event: error')) {
          throw Exception('AI model encountered an error.');
        }
      }
      client.close();

      if (!isComplete) {
        throw Exception('Connection closed before AI finished.');
      }

      // Step 4: Calculate health index
      int calculatedHealthIndex = 50;
      final lowerPrediction = finalPrediction.toLowerCase();
      if (lowerPrediction.contains('normal') || lowerPrediction.contains('healthy')) {
        calculatedHealthIndex = 100;
      } else if (lowerPrediction.contains('cataract')) {
        calculatedHealthIndex = 20;
      }

      // Step 5: Save to Supabase Database
      final nowLocal = DateTime.now().toLocal();
      await _supabase.from('examinations').insert({
        'user_id': user.id,
        'health_index': calculatedHealthIndex,
        'scan_date': nowLocal.toIso8601String(),
        'notes': 'AI Result: $finalPrediction\nDetails: $finalDetails',
        'image_url': imageUrl,
      });

      if (mounted) {
        await showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('✅ Upload Complete'),
            content: Text(
              'AI Analysis Result:\n\n'
              'Prediction: $finalPrediction\n\n'
              'Health Index: $calculatedHealthIndex/100\n\n'
              'Results saved to your history.',
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
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

      setState(() {
        _capturedImageFile = null;
        _capturedImageUrl = null;
      });
    } catch (e) {
      print('Upload error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Upload failed: ${e.toString().substring(0, 150)}'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
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
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => _checkPiConnection(retries: 3),
            color: Colors.blue,
          ),
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

              // Live Stream or Captured Photo Preview
              if (_capturedImageFile != null)
                Container(
                  width: 350,
                  height: 350,
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
                      width: 350,
                      height: 350,
                    ),
                  ),
                )
              else if (_isPiConnected)
                Container(
                  width: 350,
                  height: 350,
                  decoration: BoxDecoration(
                    color: Colors.black,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(color: Colors.blue.withOpacity(0.3), blurRadius: 30, spreadRadius: 10),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: Mjpeg(
                      stream: '$_piBaseUrl/video_feed',
                      isLive: true,
                      error: (context, error, stack) {
                        return const Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.videocam_off, size: 50, color: Colors.grey),
                              SizedBox(height: 10),
                              Text('Connecting to camera...', style: TextStyle(color: Colors.white)),
                            ],
                          ),
                        );
                      },
                      loading: (context) => const Center(
                        child: CircularProgressIndicator(color: Colors.white),
                      ),
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
                        const Icon(Icons.wifi_off, size: 60, color: Colors.grey),
                        const SizedBox(height: 16),
                        Text('Not Connected', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500, color: Colors.grey[600])),
                        const SizedBox(height: 8),
                        Text('Tap refresh to connect', style: TextStyle(fontSize: 14, color: Colors.grey[400])),
                      ],
                    ),
                  ),
                ),

              const SizedBox(height: 30),

              if (_capturedImageFile == null)
                ElevatedButton.icon(
                  onPressed: _isCapturing ? null : _capturePhoto,
                  icon: _isCapturing
                      ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
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
                          onPressed: _isUploading ? null : _retakePhoto,
                          icon: const Icon(Icons.refresh),
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
                              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
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
                    const Text('Tap Retake to go back to live view, or Upload to save', style: TextStyle(fontSize: 12, color: Colors.grey)),
                  ],
                ),

              const SizedBox(height: 40),

              Card(
                elevation: 3,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    children: [
                      const Text('Manual Entry', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.grey)),
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

  // Manual upload method
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