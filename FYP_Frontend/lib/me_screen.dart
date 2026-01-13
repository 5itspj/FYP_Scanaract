import 'package:flutter/material.dart';
import 'data_overview_screen.dart';
import 'edit_account_screen.dart';
import 'data_export_screen.dart';
import 'help_screen.dart';
import 'custom_page_route.dart';

class MeScreen extends StatefulWidget {
  const MeScreen({super.key});

  @override
  State<MeScreen> createState() => _MeScreenState();
}

class _MeScreenState extends State<MeScreen> {
  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'About me',
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),
        centerTitle: true,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16.0),
            child: GestureDetector(
              onTap: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Edit profile')),
                );
              },
              child: CircleAvatar(
                radius: 28,
                backgroundColor: Colors.blue.shade50,
                child: ClipOval(
                  child: Image.network(
                    'https://randomuser.me/api/portraits/men/45.jpg',
                    fit: BoxFit.cover,
                    width: 56,
                    height: 56,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        children: [
          const SizedBox(height: 16),

          _buildAnimatedListItem(
            index: 0,
            icon: Icons.storage_rounded,
            title: 'Data overview',
            onTap: () {
              Navigator.push(
                context,
                SlideRightRoute(page: const DataOverviewScreen()),
              );
            },
          ),

          const SizedBox(height: 8),

          _buildAnimatedListItem(
            index: 1,
            icon: Icons.person_outline_rounded,
            title: 'Edit Account',
            onTap: () {
              Navigator.push(
                context,
                SlideRightRoute(page: const EditAccountScreen()),
              );
            },
          ),

          const SizedBox(height: 8),

          _buildAnimatedListItem(
            index: 2,
            icon: Icons.file_upload_outlined,
            title: 'Data export',
            onTap: () {
              Navigator.push(
                context,
                SlideRightRoute(page: const DataExportScreen()),
              );
            },
          ),

          const SizedBox(height: 8),

          _buildAnimatedListItem(
            index: 3,
            icon: Icons.help_outline_rounded,
            title: 'Help',
            onTap: () {
              Navigator.push(
                context,
                SlideRightRoute(page: const HelpScreen()),
              );
            },
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
          child: Opacity(
            opacity: value,
            child: child,
          ),
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
        title: Text(
          title,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Colors.black87),
        ),
        trailing: const Icon(Icons.chevron_right, color: Colors.grey),
        onTap: onTap,
      ),
    );
  }
}