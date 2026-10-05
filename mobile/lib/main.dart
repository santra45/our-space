import 'package:flutter/material.dart';
import 'presentation/theme/app_theme.dart';
import 'presentation/theme/app_colors.dart';
import 'presentation/screens/lock/lock_screen.dart';
import 'presentation/screens/countdown/countdown_screen.dart';
import 'presentation/screens/polaroids/polaroid_screen.dart';
import 'presentation/screens/roulette/date_roulette_screen.dart';
import 'presentation/screens/capsule/secret_capsule_screen.dart';
import 'presentation/screens/bucketlist/bucket_list_screen.dart';
import 'presentation/screens/sync/sync_hub_screen.dart';
import 'core/crypto/vault_key.dart';
import 'core/haptics/haptics_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await HapticsService.instance.init();
  runApp(const OurSpaceApp());
}

class OurSpaceApp extends StatelessWidget {
  const OurSpaceApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Our Space 💕',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      home: const RootNavigationWrapper(),
    );
  }
}

class RootNavigationWrapper extends StatefulWidget {
  const RootNavigationWrapper({super.key});

  @override
  State<RootNavigationWrapper> createState() => _RootNavigationWrapperState();
}

class _RootNavigationWrapperState extends State<RootNavigationWrapper> {
  int _currentIndex = 0;

  final List<Widget> _screens = const [
    CountdownScreen(),
    PolaroidScreen(),
    DateRouletteScreen(),
    SecretCapsuleScreen(),
    BucketListScreen(),
  ];

  @override
  void initState() {
    super.initState();
    VaultKeyHolder.instance.addListener((_) {
      if (mounted) setState(() {});
    });
  }

  void _lockVault() {
    VaultKeyHolder.instance.lock();
    HapticsService.instance.tap();
  }

  void _openSyncHub() {
    HapticsService.instance.tick();
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const SyncHubScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!VaultKeyHolder.instance.isUnlocked) {
      return LockScreen(
        onUnlocked: () => setState(() {}),
      );
    }

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white.withValues(alpha: 0.85),
        elevation: 0,
        titleSpacing: 16,
        title: GestureDetector(
          onTap: _openSyncHub,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.matcha100,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.matcha200, width: 1.2),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: Colors.green,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                const Text(
                  'Connected 💕',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF2E6F40),
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          IconButton(
            onPressed: _openSyncHub,
            icon: const Icon(Icons.sync_rounded, color: AppColors.slate600),
            tooltip: 'Sync Hub',
          ),
          IconButton(
            onPressed: _lockVault,
            icon: const Icon(Icons.lock_outline_rounded, color: AppColors.slate600),
            tooltip: 'Lock Vault',
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: IndexedStack(
        index: _currentIndex,
        children: _screens,
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.9),
          border: const Border(top: BorderSide(color: AppColors.blush100, width: 1.5)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x15FFB6C1),
              blurRadius: 20,
              offset: Offset(0, -6),
            ),
          ],
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _navItem(0, Icons.favorite_rounded, 'Love'),
                _navItem(1, Icons.camera_alt_rounded, 'Memories'),
                _navItem(2, Icons.auto_awesome_rounded, 'Dates'),
                _navItem(3, Icons.mail_rounded, 'Letters'),
                _navItem(4, Icons.checklist_rounded, 'Bucket'),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _navItem(int index, IconData icon, String label) {
    final isSelected = _currentIndex == index;
    return GestureDetector(
      onTap: () {
        HapticsService.instance.tick();
        setState(() => _currentIndex = index);
      },
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.blush100 : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: isSelected ? AppColors.blush500 : AppColors.slate400,
              size: 22,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                color: isSelected ? AppColors.blush600 : AppColors.slate500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
