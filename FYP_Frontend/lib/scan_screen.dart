import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'main_navigator.dart';

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

  final List<String> _prompts = [
    "Please sit upright and look straight ahead",
    "Align your eyes with the camera center",
    "Hold steady... Scanning in progress",
    "Blink slowly twice",
    "Scan complete! Processing results...",
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

    Future.delayed(const Duration(seconds: 5), _nextPrompt);
  }

  void _nextPrompt() {
    if (!mounted) return;
    setState(() {
      _currentPromptIndex = (_currentPromptIndex + 1) % _prompts.length;
    });
    Future.delayed(const Duration(seconds: 5), _nextPrompt);
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
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Center(
          child: Column(
            children: [
              const SizedBox(height: 40),

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

              const SizedBox(height: 50),

              Card(
                elevation: 3,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    children: [
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
                        height: 56,
                        child: ElevatedButton(
                          onPressed: _isUploading ? null : _uploadHealthIndex,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue.shade700,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            elevation: 2,
                          ),
                          child: _isUploading
                              ? const CircularProgressIndicator(color: Colors.white)
                              : const Text('Upload Health Index', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 40),
              const Text(
                'Enter health index and tap upload\nData will appear in home chart and recent records',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: Colors.grey),
              ),
            ],
          ),
        ),
      ),
    );
  }
}