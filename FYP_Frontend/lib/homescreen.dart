import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => HomeScreenState();
}

class HomeScreenState extends State<HomeScreen> {
  final _supabase = Supabase.instance.client;

  Map<String, dynamic>? _profile;
  bool _isProfileLoaded = false;

  List<int> healthScores = [];
  List<String> chartLabels = [];

  List<Map<String, dynamic>> recentExaminations = [];

  bool _showAnimation = false;
  bool _isDeviceConnected = false;
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
        setState(() {
          _isMatching = false;
          _isDeviceConnected = true;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Device connected successfully!'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
      }
    });
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
                        onTap: _isDeviceConnected ? null : _startMatching,
                        borderRadius: BorderRadius.circular(16),
                        child: Card(
                          elevation: 3,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Row(
                              children: [
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
                                    _isDeviceConnected ? Icons.check_circle : Icons.cancel,
                                    color: _isDeviceConnected ? Colors.green : Colors.red,
                                    size: 48,
                                  ),
                                const SizedBox(width: 20),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text('Device status', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                                      const SizedBox(height: 4),
                                      Text(
                                        _isMatching ? 'Matching...' : (_isDeviceConnected ? 'Connected' : 'Disconnected'),
                                        style: TextStyle(
                                          fontSize: 20,
                                          color: _isMatching
                                              ? Colors.blue
                                              : (_isDeviceConnected ? Colors.green : Colors.red),
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      if (!_isDeviceConnected && !_isMatching)
                                        const Padding(
                                          padding: EdgeInsets.only(top: 4),
                                          child: Text(
                                            'Tap to start matching',
                                            style: TextStyle(fontSize: 12, color: Colors.grey, fontStyle: FontStyle.italic),
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