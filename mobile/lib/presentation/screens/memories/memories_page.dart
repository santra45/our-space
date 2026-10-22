import 'package:flutter/material.dart';

import '../../legacy_area.dart';
import '../../sky/sky.dart';
import '../polaroids/polaroid_wall.dart';

class MemoriesPage extends StatelessWidget {
  const MemoriesPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const SkyScaffold(
      scene: SkyScene.page,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SkyEntrance(
            child: SkyTopBar(kicker: 'Kept, just us', title: 'Memories'),
          ),
          SizedBox(height: SkySpace.lg),
          Expanded(
            child: SkyEntrance(index: 2, child: LegacyArea(child: PolaroidWall())),
          ),
        ],
      ),
    );
  }
}
