import 'package:flutter/material.dart';

import '../../legacy_area.dart';
import '../../sky/sky.dart';
import '../capsule/secret_capsule.dart';

class LettersPage extends StatelessWidget {
  const LettersPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const SkyScaffold(
      scene: SkyScene.page,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SkyEntrance(
            child: SkyTopBar(kicker: 'Fallen from the sky', title: 'Letters'),
          ),
          SizedBox(height: SkySpace.lg),
          Expanded(
            child: SkyEntrance(index: 2, child: LegacyArea(child: SecretCapsule())),
          ),
        ],
      ),
    );
  }
}
