import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:math';

class PlayingIndicator extends StatefulWidget {
  final Color color;

  const PlayingIndicator({super.key, this.color = const Color(0xFF1DB954)});

  @override
  State<PlayingIndicator> createState() => _PlayingIndicatorState();
}

class _PlayingIndicatorState extends State<PlayingIndicator> {
  Timer? _timer;
  final Random _random = Random();

  // Starting heights
  double _height1 = 4.0;
  double _height2 = 4.0;
  double _height3 = 4.0;

  @override
  void initState() {
    super.initState();
    _startAnimating();
  }

  void _startAnimating() {
    // Update less frequently to keep animation smooth and battery-friendly.
    // This erratic movement mimics a real audio visualizer.
    _timer = Timer.periodic(const Duration(milliseconds: 320), (timer) {
      if (mounted) {
        setState(() {
          // Generate a random height between 4 and 16 pixels
          _height1 = 4.0 + _random.nextInt(13);
          _height2 = 4.0 + _random.nextInt(13);
          _height3 = 4.0 + _random.nextInt(13);
        });
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel(); // Always cancel the timer when the song stops
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 16,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          _buildAnimatedBar(_height1),
          const SizedBox(width: 3),
          _buildAnimatedBar(_height2),
          const SizedBox(width: 3),
          _buildAnimatedBar(_height3),
        ],
      ),
    );
  }

  Widget _buildAnimatedBar(double height) {
    return AnimatedContainer(
      // The duration here matches the timer duration above.
      // to create a smooth, continuous morphing effect.
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeInOutSine,
      width: 3.5,
      height: height,
      decoration: BoxDecoration(
        color: widget.color,
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }
}
