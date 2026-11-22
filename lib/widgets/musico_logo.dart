import 'package:material_ui/material_ui.dart';

class MusicoLogo extends StatelessWidget {
  const MusicoLogo({this.size = 42, super.key});

  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: const BoxDecoration(
      color: Colors.black,
      shape: BoxShape.circle,
    ),
    clipBehavior: Clip.antiAlias,
    child: Transform.translate(
      offset: Offset(-size * .043, -size * .062),
      child: Transform.scale(
        scale: .9,
        child: Image.asset(
          'assets/images/musico_mark.png',
          width: size,
          height: size,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.high,
          excludeFromSemantics: true,
        ),
      ),
    ),
  );
}
