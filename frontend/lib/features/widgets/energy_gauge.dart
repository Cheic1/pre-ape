import 'dart:math';
import 'package:flutter/material.dart';
import 'package:pre_ape/core/constants/app_colors.dart';
import 'package:pre_ape/core/constants/app_spacing.dart';
import 'package:pre_ape/core/constants/app_text_styles.dart';
import 'package:pre_ape/core/scoring.dart';

class EnergyClass {
  /// Scala A4…G con i colori dell'etichetta APE (verde → rosso).
  static const List<EnergyClassData> classes = [
    EnergyClassData(letter: 'A4', color: Color(0xFF00853F), description: 'Eccellente'),
    EnergyClassData(letter: 'A3', color: Color(0xFF2E9E3E), description: 'Ottima'),
    EnergyClassData(letter: 'A2', color: Color(0xFF5DB33D), description: 'Molto buona'),
    EnergyClassData(letter: 'A1', color: Color(0xFF8CC63F), description: 'Buona'),
    EnergyClassData(letter: 'B', color: Color(0xFFC9D92B), description: 'Discreta'),
    EnergyClassData(letter: 'C', color: Color(0xFFFFD21B), description: 'Media'),
    EnergyClassData(letter: 'D', color: Color(0xFFFBB01F), description: 'Sufficiente'),
    EnergyClassData(letter: 'E', color: Color(0xFFF47B20), description: 'Scarsa'),
    EnergyClassData(letter: 'F', color: Color(0xFFEE3B24), description: 'Molto scarsa'),
    EnergyClassData(letter: 'G', color: Color(0xFFC81E1E), description: 'Pessima'),
  ];

  static EnergyClassData of(String letter) =>
      classes.firstWhere((c) => c.letter == letter, orElse: () => classes.last);
}

class EnergyClassData {
  final String letter;
  final Color color;
  final String description;

  const EnergyClassData({
    required this.letter,
    required this.color,
    required this.description,
  });
}

class EnergyGauge extends StatelessWidget {
  /// Server score 0–100 (null = estimate not available yet).
  final double? score;
  final double size;

  const EnergyGauge({
    super.key,
    required this.score,
    this.size = 180,
  });

  /// Mapping delegato a `core/scoring.dart`: stessa tabella `EnergyClass.classes`.
  EnergyClassData get currentClass =>
      EnergyClass.classes[9 - energyClassIndexForScore(score ?? 0)];

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
          ...AppShadows.card,
        ],
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: Size(size, size),
            painter: _GaugeArcPainter(
              score: score ?? 0,
              backgroundColor: AppColors.border,
              progressColor: score == null ? AppColors.border : currentClass.color,
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                score == null ? '–' : currentClass.letter,
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: size * 0.28,
                  fontWeight: FontWeight.w700,
                  color: score == null ? AppColors.textMuted : currentClass.color,
                  height: 1,
                ),
              ),
              if (size >= 120) ...[
                const SizedBox(height: 4),
                Text(
                  score == null ? 'in calcolo' : currentClass.description,
                  style: AppTextStyles.labelMedium,
                ),
              ],
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
  final double? score;
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