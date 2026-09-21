import 'package:flutter/material.dart';

class SurveyData {
  String? address;
  double? squareMeters;
  double? avgHeight;
  double currentScore = 30.0;

  String? wallThickness;
  String? windowType;
  String? heatingType;
  String? generatorType;
  List<String>? photoPaths;

  SurveyData copyWith({
    String? address,
    double? squareMeters,
    double? avgHeight,
    double? currentScore,
    String? wallThickness,
    String? windowType,
    String? heatingType,
    String? generatorType,
    List<String>? photoPaths,
  }) {
    return SurveyData()
      ..address = address ?? this.address
      ..squareMeters = squareMeters ?? this.squareMeters
      ..avgHeight = avgHeight ?? this.avgHeight
      ..currentScore = currentScore ?? this.currentScore
      ..wallThickness = wallThickness ?? this.wallThickness
      ..windowType = windowType ?? this.windowType
      ..heatingType = heatingType ?? this.heatingType
      ..generatorType = generatorType ?? this.generatorType
      ..photoPaths = photoPaths ?? this.photoPaths;
  }
}

class SurveyNotifier extends ChangeNotifier {
  SurveyData _data = SurveyData();
  int _currentStep = 1;

  SurveyData get data => _data;
  int get currentStep => _currentStep;

  void updateAddress(String address) {
    _data = _data.copyWith(address: address);
    _recalculateScore();
    notifyListeners();
  }

  void updateSquareMeters(double mq) {
    _data = _data.copyWith(squareMeters: mq);
    _recalculateScore();
    notifyListeners();
  }

  void updateAvgHeight(double height) {
    _data = _data.copyWith(avgHeight: height);
    _recalculateScore();
    notifyListeners();
  }

  void updateWallThickness(String wt) {
    _data = _data.copyWith(wallThickness: wt);
    _recalculateScore();
    notifyListeners();
  }

  void updateWindowType(String wt) {
    _data = _data.copyWith(windowType: wt);
    _recalculateScore();
    notifyListeners();
  }

  void updateHeatingType(String ht) {
    _data = _data.copyWith(heatingType: ht);
    _recalculateScore();
    notifyListeners();
  }

  void updateGeneratorType(String gt) {
    _data = _data.copyWith(generatorType: gt);
    _recalculateScore();
    notifyListeners();
  }

  void nextStep() {
    if (_currentStep < 4) {
      _currentStep++;
      notifyListeners();
    }
  }

  void previousStep() {
    if (_currentStep > 1) {
      _currentStep--;
      notifyListeners();
    }
  }

  void _recalculateScore() {
    double score = 30.0;

    if (_data.squareMeters != null) {
      score += (_data.squareMeters! / 100).clamp(0, 20);
    }

    switch (_data.wallThickness) {
      case '>40cm':
        score += 25;
        break;
      case '30-40cm':
        score += 15;
        break;
      case '<30cm':
        score += 5;
        break;
    }

    if (_data.windowType != null) {
      if (_data.windowType!.contains('Triplo')) {
        score += 15;
      } else if (_data.windowType!.contains('Doppio')) {
        score += 10;
      } else {
        score += 5;
      }
    }

    switch (_data.heatingType) {
      case 'Pompa di Calore':
        score += 10;
        break;
      case 'Condensazione':
        score += 8;
        break;
      case 'Pellet':
        score += 6;
        break;
      default:
        score += 2;
    }

    _data = _data.copyWith(currentScore: score.clamp(0, 100));
  }
}

final surveyProvider = ChangeNotifierProvider<SurveyNotifier>((ref) {
  return SurveyNotifier();
});