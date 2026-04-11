import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'data_overview_screen.dart';
import 'edit_account_screen.dart';
import 'data_export_screen.dart';
import 'help_screen.dart';
import 'custom_page_route.dart';
import 'main_navigator.dart';

class MeScreen extends StatefulWidget {
  const MeScreen({super.key});

  @override
  State<MeScreen> createState() => _MeScreenState();
}

class _MeScreenState extends State<MeScreen> {
  final _supabase = Supabase.instance.client;

  Map<String, dynamic>? _profile;
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadUserProfile();
  }

  Future<void> _loadUserProfile() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) {
        setState(() {
          _errorMessage = 'No logged in user detected';
          _isLoading = false;
        });
        return;
      }

      final data = await _supabase
          .from('profiles')
          .select()
          .eq('id', user.id)
          .single();

      setState(() {
        _profile = data;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to load profile, please try again later';
        _isLoading = false;
      });
      debugPrint('Profile load error: $e');
    }
  }

  Future<void> _signOut() async {
    await _supabase.auth.signOut();
    if (mounted) {
      Navigator.pushReplacementNamed(context, '/');
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = _supabase.auth.currentUser;
    final displayName = _profile?['full_name'] ?? user?.email?.split('@')[0] ?? 'User';
    final patientId = _profile?['patient_id'] ?? 'Not set';
    final avatarUrl = _profile?['avatar_url'] as String? ?? 
        'https://randomuser.me/api/portraits/men/45.jpg';

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text('Me', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.black87)),
        centerTitle: true,
        actions: [
          IconButton(icon: const Icon(Icons.logout, color: Colors.black87), onPressed: _signOut),
          Padding(
            padding: const EdgeInsets.only(right: 16.0),
            child: CircleAvatar(
              radius: 28,
              backgroundColor: Colors.blue.shade50,
              child: ClipOval(
                child: Image.network(avatarUrl, fit: BoxFit.cover, width: 56, height: 56,
                    errorBuilder: (_, __, ___) => const Icon(Icons.person, size: 40, color: Colors.grey)),
              ),
            ),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
              ? Center(child: Text(_errorMessage!))
              : ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  children: [
                    const SizedBox(height: 16),

                    Card(
                      elevation: 2,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          children: [
                            Text(displayName, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 4),
                            Text(user?.email ?? '', style: TextStyle(fontSize: 15, color: Colors.grey.shade700)),
                            const SizedBox(height: 12),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Text('Patient ID: ', style: TextStyle(fontSize: 15)),
                                Text(patientId, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 24),

                    _buildAnimatedListItem(
                      index: 0,
                      icon: Icons.storage_rounded,
                      title: 'Data Overview',
                      onTap: () => Navigator.push(context, SlideRightRoute(page: const DataOverviewScreen())),
                    ),

                    const SizedBox(height: 8),
                    _buildAnimatedListItem(
                      index: 1,
                      icon: Icons.person_outline_rounded,
                      title: 'Edit Account',
                      onTap: () async {
                        final updated = await Navigator.push(
                          context,
                          SlideRightRoute(page: const EditAccountScreen()),
                        );

                        if (updated == true && mounted) {
                          _loadUserProfile();

                          Navigator.pushAndRemoveUntil(
                            context,
                            MaterialPageRoute(builder: (context) => const MainNavigator()),
                            (route) => false,
                          );
                        }
                      },
                    ),

                    const SizedBox(height: 8),

                    _buildAnimatedListItem(
                      index: 2,
                      icon: Icons.file_upload_outlined,
                      title: 'Data Export',
                      onTap: () => Navigator.push(context, SlideRightRoute(page: const DataExportScreen())),
                    ),

                    const SizedBox(height: 8),

                    _buildAnimatedListItem(
                      index: 3,
                      icon: Icons.help_outline_rounded,
                      title: 'Help',
                      onTap: () => Navigator.push(context, SlideRightRoute(page: const HelpScreen())),
                    ),
                  ],
                ),
    );
  }

  Widget _buildAnimatedListItem({
    required int index,
    required IconData icon,
    required String title,
    required VoidCallback onTap,
  }) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: Duration(milliseconds: 300 + (index * 100)),
      curve: Curves.easeOut,
      builder: (context, value, child) {
        return Transform.translate(
          offset: Offset(0, (1 - value) * 20),
          child: Opacity(opacity: value, child: child),
        );
      },
      child: _buildListItem(icon: icon, title: title, onTap: onTap),
    );
  }

  Widget _buildListItem({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
  }) {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        leading: Container(
          width: 50,
          height: 50,
          decoration: BoxDecoration(
            color: Colors.blue.shade50,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: Colors.blue.shade700, size: 28),
        ),
        title: Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Colors.black87)),
        trailing: const Icon(Icons.chevron_right, color: Colors.grey),
        onTap: onTap,
      ),
    );
  }
}