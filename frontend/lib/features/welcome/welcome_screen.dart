import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_colors.dart';
import '../../ui/motion/entrance.dart';
import '../../ui/widgets/brand_stage.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  void _explain(BuildContext context) => showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Good food. A few taps away.',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 20),
            const ListTile(
              leading: Icon(Icons.restaurant_menu),
              title: Text('Find your kitchen'),
              subtitle: Text('Explore restaurants and their real menus.'),
            ),
            const ListTile(
              leading: Icon(Icons.shopping_bag_outlined),
              title: Text('Make it yours'),
              subtitle: Text('Add your dishes and place an order.'),
            ),
            const ListTile(
              leading: Icon(Icons.receipt_long_outlined),
              title: Text('Follow every step'),
              subtitle: Text(
                'Track payment, confirmation and driver assignment.',
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () {
                Navigator.pop(context);
                context.go('/login');
              },
              child: const Text('Continue with email'),
            ),
          ],
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.brandRed,
    body: BrandStage(
      child: SafeArea(
        child: LayoutBuilder(
          builder: (context, box) {
            final wide = box.maxWidth >= 900;
            final large = MediaQuery.textScalerOf(context).scale(16) > 21;
            final heading = Entrance(
              child: Semantics(
                header: true,
                child: Text(
                  'Welcome to\nQuickBite',
                  textAlign: wide ? TextAlign.left : TextAlign.center,
                  style: TextStyle(
                    fontSize: wide ? 82 : (box.maxHeight < 700 ? 52 : 62),
                    fontWeight: FontWeight.w900,
                    height: .98,
                    letterSpacing: -2.6,
                    color: Colors.white,
                  ),
                ),
              ),
            );
            final badge = Text(
              'GOOD FOOD. GREAT MOOD.',
              textAlign: wide ? TextAlign.left : TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 2,
              ),
            );
            final actions = Entrance(
              index: 2,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  FilledButton.icon(
                    onPressed: () => context.go('/login'),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFFFDAD1),
                      foregroundColor: AppColors.ink,
                      minimumSize: const Size.fromHeight(52),
                    ),
                    icon: const Icon(Icons.mail_outline_rounded, size: 19),
                    label: const Text('Continue with email'),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () => _explain(context),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white70),
                      minimumSize: const Size.fromHeight(50),
                    ),
                    icon: const Icon(Icons.delivery_dining_outlined, size: 20),
                    label: const Text('How it works'),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'Find your favourites. We’ll take it from here.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            );
            if (wide) {
              return Center(
                child: SingleChildScrollView(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1160),
                    child: Padding(
                      padding: const EdgeInsets.all(48),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                badge,
                                const SizedBox(height: 30),
                                heading,
                                const SizedBox(height: 28),
                                const Text(
                                  'Your next great bite starts here.',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 19,
                                  ),
                                ),
                                const SizedBox(height: 40),
                                SizedBox(width: 390, child: actions),
                              ],
                            ),
                          ),
                          const Expanded(
                            child: SizedBox(height: 520, child: BurgerHero()),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }
            Widget composition(double height) => SizedBox(
              height: height,
              child: Column(
                children: [
                  SizedBox(height: box.maxHeight > 750 ? 40 : 20),
                  badge,
                  const SizedBox(height: 22),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: heading,
                  ),
                  Expanded(
                    child: Transform.scale(
                      scale: 1.25,
                      child: const BurgerHero(),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 18),
                    child: actions,
                  ),
                ],
              ),
            );
            return SingleChildScrollView(
              child: composition(math.max(box.maxHeight, large ? 850 : 570)),
            );
          },
        ),
      ),
    ),
  );
}
