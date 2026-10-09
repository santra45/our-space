import 'dart:math';
import 'package:flutter/material.dart';
import 'package:confetti/confetti.dart';
import '../../theme/app_colors.dart';
import '../../../models/date_idea.dart';
import '../../../core/haptics/haptics_service.dart';

class DateRouletteScreen extends StatefulWidget {
  const DateRouletteScreen({super.key});

  @override
  State<DateRouletteScreen> createState() => _DateRouletteScreenState();
}

class _DateRouletteScreenState extends State<DateRouletteScreen> {
  late ConfettiController _confettiController;
  final List<Offset?> _scratchPoints = [];
  bool _isRevealed = false;

  final List<DateIdea> _sampleIdeas = [
    DateIdea(id: 'd1', title: 'Stargazing Picnic 🌌', description: 'Pack hot cocoa and a blanket, find a quiet dark spot and watch the stars.', updatedAt: 0),
    DateIdea(id: 'd2', title: 'Cook a 3-Course Dinner 🍝', description: 'Pick a cuisine we have never cooked before and prepare it together from scratch.', updatedAt: 0),
    DateIdea(id: 'd3', title: 'Living Room Fort & Movies ⛺', description: 'Build a giant cozy blanket fort, dim the lights and marathon our favorite childhood movies.', updatedAt: 0),
    DateIdea(id: 'd4', title: 'Sunset Drive & Gelato 🍦', description: 'Drive somewhere with an open view for sunset, followed by late-night dessert.', updatedAt: 0),
    DateIdea(id: 'd5', title: 'Bookstore Scavenger Hunt 📚', description: 'Go to a bookstore and find each other a book to read, with handwritten notes inside.', updatedAt: 0),
  ];

  late DateIdea _currentIdea;

  @override
  void initState() {
    super.initState();
    _confettiController = ConfettiController(duration: const Duration(seconds: 3));
    _pickRandomIdea();
  }

  @override
  void dispose() {
    _confettiController.dispose();
    super.dispose();
  }

  void _pickRandomIdea() {
    setState(() {
      _currentIdea = _sampleIdeas[Random().nextInt(_sampleIdeas.length)];
      _scratchPoints.clear();
      _isRevealed = false;
    });
  }

  void _triggerReveal() {
    if (_isRevealed) return;
    setState(() => _isRevealed = true);
    HapticsService.instance.celebration();
    _confettiController.play();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: AppColors.blush50,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text('Date Roulette 🎲', style: theme.textTheme.headlineSmall),
        centerTitle: true,
      ),
      body: Stack(
        alignment: Alignment.topCenter,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'What should we do next? 💕',
                  style: theme.textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                Text(
                  'Scratch the silver card below with your finger to reveal your date idea!',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 32),

                Container(
                  width: double.infinity,
                  height: 240,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(28),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x1AFF5480),
                        blurRadius: 24,
                        offset: Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Stack(
                    children: [
                      Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                _currentIdea.title,
                                textAlign: TextAlign.center,
                                style: theme.textTheme.displayMedium?.copyWith(
                                  color: AppColors.blush600,
                                ),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                _currentIdea.description,
                                textAlign: TextAlign.center,
                                style: theme.textTheme.bodyLarge?.copyWith(
                                  color: AppColors.slate700,
                                  height: 1.4,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                      if (!_isRevealed)
                        GestureDetector(
                          onPanUpdate: (details) {
                            setState(() {
                              final renderBox = context.findRenderObject() as RenderBox?;
                              if (renderBox != null) {
                                _scratchPoints.add(details.localPosition);
                              }
                            });
                            HapticsService.instance.tick();
                            if (_scratchPoints.length > 35) {
                              _triggerReveal();
                            }
                          },
                          onPanEnd: (_) => _scratchPoints.add(null),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(28),
                            child: CustomPaint(
                              painter: _ScratchPainter(points: _scratchPoints),
                              size: Size.infinite,
                              child: Container(
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                    colors: [Color(0xFFE2E8F0), Color(0xFFCBD5E1), Color(0xFFE2E8F0)],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  ),
                                  borderRadius: BorderRadius.circular(28),
                                ),
                                child: Center(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      const Icon(Icons.touch_app_rounded, color: AppColors.slate500, size: 36),
                                      const SizedBox(height: 8),
                                      Text(
                                        'SCRATCH HERE 💕',
                                        style: theme.textTheme.titleMedium?.copyWith(
                                          color: AppColors.slate600,
                                          letterSpacing: 2,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),

                const SizedBox(height: 36),

                OutlinedButton.icon(
                  onPressed: _pickRandomIdea,
                  icon: const Icon(Icons.refresh_rounded, color: AppColors.blush500),
                  label: Text('Spin Again 🎲', style: theme.textTheme.titleMedium?.copyWith(color: AppColors.blush500)),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                    side: const BorderSide(color: AppColors.blush300, width: 1.5),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  ),
                ),
              ],
            ),
          ),

          ConfettiWidget(
            confettiController: _confettiController,
            blastDirectionality: BlastDirectionality.explosive,
            shouldLoop: false,
            colors: const [
              AppColors.blush400,
              AppColors.blush500,
              AppColors.lavender400,
              AppColors.matcha300,
              Colors.amber,
            ],
          ),
        ],
      ),
    );
  }
}

class _ScratchPainter extends CustomPainter {
  final List<Offset?> points;
  _ScratchPainter({required this.points});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.transparent
      ..blendMode = BlendMode.clear
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 44.0;

    for (int i = 0; i < points.length - 1; i++) {
      if (points[i] != null && points[i + 1] != null) {
        canvas.drawLine(points[i]!, points[i + 1]!, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _ScratchPainter oldDelegate) => true;
}
