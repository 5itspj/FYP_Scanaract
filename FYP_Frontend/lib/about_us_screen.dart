import 'package:flutter/material.dart';

class AboutUsScreen extends StatelessWidget {
  AboutUsScreen({super.key});

  final List<Creator> creators = [
    Creator(
      name: "Dr. Dani S. Assi",           
      studentId: "",
      imageUrl: "assets/images/Dani.png",   
      isSupervisor: true,
    ),
    Creator(
      name: "SHAH Pooja Zenit (PJ)​",
      studentId: "13125135",
      imageUrl: "assets/images/pj.jpg",
      isSupervisor: false,
    ),
    Creator(
      name: "Ke Yankai (KK)",
      studentId: "12979014",
      imageUrl: "assets/images/kk.jpg",
      isSupervisor: false,
    ),
    Creator(
      name: "Fu Yuhao (Colin)​",
      studentId: "12987211",
      imageUrl: "assets/images/colin.jpg",
      isSupervisor: false,
    ),
    Creator(
      name: "Li Xilin (Penn)",
      studentId: "12815806",
      imageUrl: "assets/images/penn.jpg",
      isSupervisor: false,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text('About Us'),
        backgroundColor: Colors.white,
        elevation: 1,
        foregroundColor: Colors.black87,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Center(
              child: Column(
                children: [
                  Icon(Icons.remove_red_eye_outlined, size: 80, color: Colors.blue),
                  SizedBox(height: 16),
                  Text(
                    'Ocular Disease Monitor',
                    style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Developed by Team 5',
                    style: TextStyle(fontSize: 16, color: Colors.grey),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 40),

            const Text(
              'Our Team',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),

            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: creators.length,
              itemBuilder: (context, index) {
                final creator = creators[index];
                return _buildCreatorCard(creator);
              },
            ),

            const SizedBox(height: 40),

            const Center(
              child: Text(
                '© 2026 Ocular Disease Monitor Team\nAll Rights Reserved',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey, fontSize: 14),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCreatorCard(Creator creator) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            CircleAvatar(
              radius: 40,
              backgroundImage: AssetImage(creator.imageUrl),
              backgroundColor: Colors.grey[200],
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    creator.name,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 6),

                  Text(
                    creator.isSupervisor 
                        ? 'Supervisor' 
                        : 'Student ID: ${creator.studentId}',
                    style: TextStyle(
                      fontSize: 15,
                      color: creator.isSupervisor ? Colors.orange : Colors.grey,
                      fontWeight: creator.isSupervisor ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class Creator {
  final String name;
  final String studentId;
  final String imageUrl;
  final bool isSupervisor;

  Creator({
    required this.name,
    required this.studentId,
    required this.imageUrl,
    this.isSupervisor = false,
  });
}