import 'package:flutter/material.dart';

class BordoMaviIcon extends StatelessWidget {
  const BordoMaviIcon({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 100,
      height: 100,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF800000), // Bordo
            Color(0xFF0000CD), // Mavi
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 10,
            spreadRadius: 2,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Arka plan deseni
          CustomPaint(
            size: const Size(100, 100),
            painter: BackgroundPatternPainter(),
          ),
          // Ana ikon
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.camera_alt,
              color: Colors.white,
              size: 30,
            ),
          ),
          // Köşe ikonları
          Positioned(
            top: 12,
            right: 12,
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Icon(
                Icons.chat_bubble,
                color: Colors.white,
                size: 16,
              ),
            ),
          ),
          Positioned(
            bottom: 12,
            left: 12,
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Icon(
                Icons.favorite,
                color: Colors.white,
                size: 16,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class BackgroundPatternPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withOpacity(0.1)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    // Dikey çizgiler
    for (var i = 0; i < size.width; i += 15) {
      canvas.drawLine(
        Offset(i.toDouble(), 0),
        Offset(i.toDouble(), size.height),
        paint,
      );
    }

    // Yatay çizgiler
    for (var i = 0; i < size.height; i += 15) {
      canvas.drawLine(
        Offset(0, i.toDouble()),
        Offset(size.width, i.toDouble()),
        paint,
      );
    }

    // Köşe süslemeleri
    final cornerPaint = Paint()
      ..color = Colors.white.withOpacity(0.2)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    // Sol üst köşe
    canvas.drawPath(
      Path()
        ..moveTo(0, 0)
        ..lineTo(20, 0)
        ..lineTo(0, 20),
      cornerPaint,
    );

    // Sağ üst köşe
    canvas.drawPath(
      Path()
        ..moveTo(size.width, 0)
        ..lineTo(size.width - 20, 0)
        ..lineTo(size.width, 20),
      cornerPaint,
    );

    // Sol alt köşe
    canvas.drawPath(
      Path()
        ..moveTo(0, size.height)
        ..lineTo(20, size.height)
        ..lineTo(0, size.height - 20),
      cornerPaint,
    );

    // Sağ alt köşe
    canvas.drawPath(
      Path()
        ..moveTo(size.width, size.height)
        ..lineTo(size.width - 20, size.height)
        ..lineTo(size.width, size.height - 20),
      cornerPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
} 