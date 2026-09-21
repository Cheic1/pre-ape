import 'dart:math';
import 'package:flutter/material.dart';
import 'package:pre_ape/core/constants/app_colors.dart';
import 'package:pre_ape/core/constants/app_text_styles.dart';

class EnergyClass {
  static const List<EnergyClassData> classes = [
    EnergyClassData(letter: 'A4', range: '>= 120', color: Color(0xFF10B981), description: 'Eccellente'),
    EnergyClassData(letter: 'A3', range: '90 - 120', color: Color(0xFF34D399), description: 'Molto buono'),
    EnergyClassData(letter: 'A2', range: '65 - 90', color: Color(0xFF6EE7B7), description: 'Buono'),
    EnergyClassData(letter: 'A1', range: '55 - 65', color: Color(0xFFA7F3D0), description: 'Ottimo'),
    EnergyClassData(letter: 'B', range: '40 - 55', color: Color(0xFFFBBF24), description: 'Discreto'),
    EnergyClassData(letter: 'C', range: '30 - 40', color: Color(0xFFF59E0B), description: 'Medio'),
    EnergyClassData(letter: 'D', range: '20 - 30', color: Color(0xFFFB923C), description: 'Sufficiente'),
    EnergyClassData(letter: 'E', range: '15 - 20', color: Color(0xFFFC814A), description: 'Poco efficiente'),
    EnergyClassData(letter: 'F', range: '10 - 15', color: Color(0xFFF97316), description: 'Efficiente'),
    EnergyClassData(letter: 'G', range: '< 10', color: Color(0xFFEF4444), description: 'Molto inefficiente'),
  ];
}

class EnergyClassData {
  final String letter;
  final String range;
  final Color color;
  final String description;

  EnergyClassData({
    required this.letter,
    required this.range,
    required this.color,
    required this.description,
  });
}

class EnergyGauge extends StatelessWidget {
  final double score;
  final double size;

  const EnergyGauge({
    super.key,
    required this.score,
    this.size = 180,
  });

  EnergyClassData get currentClass {
    final normalized = score.clamp(0, 100);
    final index = (normalized / 100 * 9).round().clamp(0, 9);
    return EnergyClass.classes[9 - index];
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.surface,
        border: Border.all(
          color: currentClass.color.withValues(alpha: 0.3),
          width: 2,
        ),
        boxShadow: [
          BoxShadow(
            color: currentClass.color.withValues(alpha: 0.15),
            blurRadius: 24,
            offset: const Offset(0, 0),
          ),
          AppShadows.card,
        ],
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: Size(size, size),
            painter: _GaugeArcPainter(
              score: score,
              backgroundColor: AppColors.border,
              progressColor: currentClass.color,
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                currentClass.letter,
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: size * 0.28,
                  fontWeight: FontWeight.w700,
                  color: currentClass.color,
                  height: 1,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                currentClass.description,
                style: AppTextStyles.labelMedium,
              ),
              const SizedBox(height: 2),
              Text(
                'Score: ${score.toInt()}%',
                style: AppTextStyles.bodySmall,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _GaugeArcPainter extends CustomPainter {
  final double score;
  final Color backgroundColor;
  final Color progressColor;

  _GaugeArcPainter({
    required this.score,
    required this.backgroundColor,
    required this.progressColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 8;

    final backgroundPaint = Paint()
      ..color = backgroundColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -pi * 1.25,
      pi * 2.5,
      false,
      backgroundPaint,
    );

    final progressPaint = Paint()
      ..color = progressColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8
      ..strokeCap = StrokeCap.round;

    final sweepAngle = (score / 100) * pi * 2.5;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -pi * 1.25,
      sweepAngle,
      false,
      progressPaint,
    );
  }

  @override
  bool shouldRepaint(_GaugeArcPainter oldDelegate) =>
      oldDelegate.score != score ||
      oldDelegate.backgroundColor != backgroundColor ||
      oldDelegate.progressColor != progressColor;
}

class CompactEnergyGauge extends StatelessWidget {
  final double score;
  final double size;

  const CompactEnergyGauge({
    super.key,
    required this.score,
    this.size = 70,
  });

  @override
  Widget build(BuildContext context) {
    return EnergyGauge(score: score, size: size);
  }
}