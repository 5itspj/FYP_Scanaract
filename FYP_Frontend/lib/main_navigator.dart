import 'package:flutter/material.dart';
import 'homescreen.dart';
import 'historyscreen.dart';
import 'me_screen.dart';
import 'about_us_screen.dart';       
import 'scan_screen.dart';

class MainNavigator extends StatefulWidget {
  const MainNavigator({super.key});

  @override
  State<MainNavigator> createState() => _MainNavigatorState();
}

class _MainNavigatorState extends State<MainNavigator> with TickerProviderStateMixin {
  int _selectedIndex = 0;
  int _previousIndex = 0;

  late final List<Widget> _pages;

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  late AnimationController _pupilController;
  late Animation<Offset> _pupilAnimation;

  @override
  void initState() {
    super.initState();

    _pages = [
      HomeScreen(),          
      HistoryScreen(),       
      ScanScreen(),          
      MeScreen(),            
      AboutUsScreen(),      
    ];

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.95, end: 1.05).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _pupilController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );

    _pupilAnimation = Tween<Offset>(
      begin: _getPupilOffset(_previousIndex),
      end: _getPupilOffset(_selectedIndex),
    ).animate(
      CurvedAnimation(parent: _pupilController, curve: Curves.easeInOutCubic),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _pupilController.dispose();
    super.dispose();
  }

  void _onItemTapped(int index) {
    if (index == _selectedIndex) return;

    setState(() {
      _previousIndex = _selectedIndex;
      _selectedIndex = index;
    });

    _pupilAnimation = Tween<Offset>(
      begin: _getPupilOffset(_previousIndex),
      end: _getPupilOffset(_selectedIndex),
    ).animate(
      CurvedAnimation(parent: _pupilController, curve: Curves.easeInOutCubic),
    );

    _pupilController.forward(from: 0.0);
  }

  Offset _getPupilOffset(int index) {
    const double maxOffset = 6.0;
    switch (index) {
      case 0: return Offset(-maxOffset, -maxOffset);
      case 1: return Offset(-maxOffset, maxOffset);
      case 2: return Offset(0, 0);
      case 3: return Offset(maxOffset, maxOffset);  
      case 4: return Offset(maxOffset, -maxOffset);  
      default: return Offset(0, 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _selectedIndex,
        children: _pages,
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: _onItemTapped,
        selectedItemColor: Colors.blue.shade700,
        unselectedItemColor: Colors.grey,
        backgroundColor: Colors.white,
        type: BottomNavigationBarType.fixed,
        elevation: 8,
        items: [
          const BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
          const BottomNavigationBarItem(icon: Icon(Icons.history), label: 'History'),
          BottomNavigationBarItem(
            icon: AnimatedBuilder(
              animation: Listenable.merge([_pulseAnimation, _pupilAnimation]),
              builder: (context, child) {
                final offset = _pupilAnimation.value;
                return Transform.scale(
                  scale: _pulseAnimation.value,
                  child: SizedBox(
                    width: 50,
                    height: 50,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.blue.shade700,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.blue.withOpacity(0.5),
                                blurRadius: 12,
                                spreadRadius: 2,
                              ),
                            ],
                          ),
                        ),
                        Container(
                          width: 28,
                          height: 28,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white,
                          ),
                        ),
                        Transform.translate(
                          offset: offset,
                          child: Container(
                            width: 14,
                            height: 14,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.black87,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
            label: 'scan',
          ),
          const BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Me'),
          const BottomNavigationBarItem(icon: Icon(Icons.info_outline), label: 'About Us'),  
        ],
      ),
    );
  }
}