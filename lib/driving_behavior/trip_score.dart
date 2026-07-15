/// Driving score algorithm – pure function, easy to unit test.
///
/// Score starts at 100 and deductions are subtracted proportionally
/// per event. Clamped to [0, 100].
///
/// Weights chosen so a typical mild drive stays ≥ 85.
class TripScore {
  static const double _brakeDeduction = 4.0;
  static const double _accelDeduction = 3.0;
  static const double _cornerDeduction = 2.0;
  static const double _speedingDeductionPerPct = 0.2; // per 1 % time over limit

  /// Returns an integer score in [0, 100].
  static int calculate({
    required int harshBrakeCount,
    required int harshAccelCount,
    required int sharpCornerCount,
    required double timeOverLimitPct,
  }) {
    final deduction = harshBrakeCount * _brakeDeduction +
        harshAccelCount * _accelDeduction +
        sharpCornerCount * _cornerDeduction +
        timeOverLimitPct * _speedingDeductionPerPct;

    return (100 - deduction).clamp(0, 100).round();
  }

  /// Returns a human-readable label for a score.
  static String label(int score) {
    if (score >= 90) return 'Excellent';
    if (score >= 75) return 'Good';
    if (score >= 55) return 'Fair';
    if (score >= 35) return 'Poor';
    return 'Dangerous';
  }

  /// Returns a color hex string associated with the score.
  static ({int r, int g, int b}) scoreColor(int score) {
    if (score >= 90) return (r: 0x00, g: 0xE5, b: 0x76); // green
    if (score >= 75) return (r: 0x76, g: 0xD8, b: 0x00); // lime
    if (score >= 55) return (r: 0xFF, g: 0xC1, b: 0x07); // amber
    if (score >= 35) return (r: 0xFF, g: 0x72, b: 0x00); // orange
    return (r: 0xFF, g: 0x1A, b: 0x1A); // red
  }
}
