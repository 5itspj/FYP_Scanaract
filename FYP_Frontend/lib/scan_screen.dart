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
  File? _capturedImageFile;

  bool _isPiConnected = false;
  final String _piBaseUrl = 'http://10.42.0.1:8081';

  final _supabase = Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(vsync: this, duration: const Duration(seconds: 3))..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.9, end: 1.1).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    Future.delayed(const Duration(milliseconds: 500), _checkPiConnection);
  }

  Future<void> _checkPiConnection({int retries = 3}) async {
    final connectivityResult = await Connectivity().checkConnectivity();
    if (connectivityResult != ConnectivityResult.wifi) {
      setState(() => _isPiConnected = false);
      return;
    }

    for (int i = 0; i < retries; i++) {
      try {
        final response = await http.get(Uri.parse('$_piBaseUrl/photos')).timeout(const Duration(seconds: 2));
        if (response.statusCode == 200) {
          if (mounted) setState(() => _isPiConnected = true);
          return;
        }
      } catch (e) {
        if (i < retries - 1) await Future.delayed(const Duration(milliseconds: 500));
      }
    }
    if (mounted) setState(() => _isPiConnected = false);
  }

  Future<void> _capturePhoto() async {
    await _checkPiConnection();
    if (!_isPiConnected) {
      final shouldConnect = await _showPiConnectionDialog();
      if (shouldConnect) {
        await _openWifiSettings();
        await _checkPiConnection(retries: 5);
      }
      if (!_isPiConnected) return;
    }

    setState(() => _isCapturing = true);

    try {
      final captureResponse = await http.get(Uri.parse('$_piBaseUrl/capture')).timeout(const Duration(seconds: 10));
      if (captureResponse.statusCode != 200) throw Exception('Failed to capture');

      final result = jsonDecode(captureResponse.body);
      final filename = result['filename'];

      final imageResponse = await http.get(Uri.parse('$_piBaseUrl/static/photos/$filename')).timeout(const Duration(seconds: 10));
      if (imageResponse.statusCode != 200) throw Exception('Failed to download');

      final tempDir = await getTemporaryDirectory();
      final file = File('${tempDir.path}/$filename');
      await file.writeAsBytes(imageResponse.bodyBytes);

      setState(() => _capturedImageFile = file);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Photo captured successfully!'), backgroundColor: Colors.green),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Capture failed: $e'), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _isCapturing = false);
    }
  }

  // 上传到 Inspection results Bucket
  Future<void> _uploadCapturedPhoto() async {
    if (_capturedImageFile == null) return;

    setState(() => _isUploading = true);

    try {
      final user = _supabase.auth.currentUser;
      if (user == null) throw Exception('Not logged in');

      final fileExt = _capturedImageFile!.path.split('.').last;
      final fileName = '${user.id}-${DateTime.now().millisecondsSinceEpoch}.$fileExt';
      final filePath = 'inspection_results/$fileName';

      // 上传照片
      await _supabase.storage.from('inspection_results').upload(
        filePath,
        _capturedImageFile!,
        fileOptions: FileOptions(contentType: 'image/$fileExt'),
      );

      final publicUrl = _supabase.storage.from('inspection_results').getPublicUrl(filePath);

      // 保存到 examinations 表
      await _supabase.from('examinations').insert({
        'user_id': user.id,
        'image_url': publicUrl,
        'uploaded_at': DateTime.now().toIso8601String(),
        'notes': 'Eye scan from Scanaract',
        'health_index': 0,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Scan uploaded to Inspection Results successfully!'), backgroundColor: Colors.green),
        );

        setState(() => _capturedImageFile = null);

        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const MainNavigator()),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Upload failed: $e'), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  Future<bool> _showPiConnectionDialog() async {
    return await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (context) => AlertDialog(
        title: const Text('Camera Not Connected'),
        content: const Text('Please connect to the Scanaract_Wifi network first.\n\nNetwork: Scanaract_Wifi\nPassword: scanaractpi'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Open Wi-Fi Settings')),
        ],
      ),
    ) ?? false;
  }

  Future<void> _openWifiSettings() async {
    try {
      final intent = AndroidIntent(action: 'android.settings.WIFI_SETTINGS');
      await intent.launch();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not open Wi-Fi settings')));
    }
  }

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

      await _supabase.from('examinations').insert({
        'user_id': user.id,
        'health_index': index,
        'scan_date': DateTime.now().toIso8601String(),
        'notes': 'Manual test upload',
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Manual upload successful!'), backgroundColor: Colors.green));
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const MainNavigator()));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Upload failed: $e'), backgroundColor: Colors.red));
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
          IconButton(icon: const Icon(Icons.refresh), onPressed: () => _checkPiConnection(retries: 3), color: Colors.blue),
          Container(
            margin: const EdgeInsets.only(right: 16),
            child: Row(
              children: [
                Icon(_isPiConnected ? Icons.wifi : Icons.wifi_off, color: _isPiConnected ? Colors.green : Colors.red, size: 20),
                const SizedBox(width: 4),
                Text(_isPiConnected ? 'Camera' : 'Offline', style: TextStyle(fontSize: 12, color: _isPiConnected ? Colors.green : Colors.red)),
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

              if (_capturedImageFile != null)
                Container(
                  width: 350,
                  height: 350,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [BoxShadow(color: Colors.blue.withOpacity(0.3), blurRadius: 30, spreadRadius: 10)],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: Image.file(_capturedImageFile!, fit: BoxFit.cover),
                  ),
                )
              else
                ScaleTransition(
                  scale: _pulseAnimation,
                  child: Container(
                    width: 280,
                    height: 280,
                    decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white, boxShadow: [BoxShadow(color: Colors.blue.withOpacity(0.3), blurRadius: 30, spreadRadius: 10)]),
                    child: const Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.remove_red_eye, size: 80, color: Colors.blue),
                        SizedBox(height: 24),
                        Text('Position your eye in the center', textAlign: TextAlign.center, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500)),
                      ],
                    ),
                  ),
                ),

              const SizedBox(height: 30),

              if (_capturedImageFile == null)
                ElevatedButton.icon(
                  onPressed: _isCapturing ? null : _capturePhoto,
                  icon: _isCapturing ? const CircularProgressIndicator(color: Colors.white, strokeWidth: 2) : const Icon(Icons.camera_alt, size: 28),
                  label: Text(_isCapturing ? 'Capturing...' : (_isPiConnected ? 'Capture Photo' : 'Connect to Camera')),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _isPiConnected ? Colors.blue.shade700 : Colors.orange,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                  ),
                )
              else
                Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        ElevatedButton.icon(
                          onPressed: _isUploading ? null : () => setState(() => _capturedImageFile = null),
                          icon: const Icon(Icons.refresh),
                          label: const Text('Retake'),
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.grey, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30))),
                        ),
                        const SizedBox(width: 20),
                        ElevatedButton.icon(
                          onPressed: _isUploading ? null : _uploadCapturedPhoto,
                          icon: _isUploading ? const CircularProgressIndicator(color: Colors.white, strokeWidth: 2) : const Icon(Icons.cloud_upload),
                          label: const Text('Upload to Inspection Results'),
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30))),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const Text('Tap Upload to save this scan to Inspection Results', style: TextStyle(fontSize: 12, color: Colors.grey)),
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
                        decoration: InputDecoration(labelText: 'Health Index (0-100)', border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)), filled: true, fillColor: Colors.grey[50]),
                      ),
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: ElevatedButton(
                          onPressed: _isUploading ? null : _uploadHealthIndex,
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.blue.shade700, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                          child: _isUploading ? const CircularProgressIndicator(color: Colors.white) : const Text('Upload Health Index (Manual)'),
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
}