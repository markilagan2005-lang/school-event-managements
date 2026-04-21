import 'dart:math';

class Uuid {
  static String v4() {
    const chars = '0123456789abcdef';
    final random = Random();
    return List.generate(32, (i) => chars[random.nextInt(16)]).join();
  }
}
