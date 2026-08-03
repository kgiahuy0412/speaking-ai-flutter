import 'package:flutter/material.dart';

enum HomeRailEdge { left, right }

class HomeModeRail extends StatelessWidget {
  const HomeModeRail({
    required this.edge,
    required this.label,
    required this.icon,
    required this.color,
    required this.onPressed,
    this.badge,
    this.expanded = false,
    super.key,
  });

  final HomeRailEdge edge;
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onPressed;
  final String? badge;
  final bool expanded;

  static const double _collapsedWidth = 47;
  static const double _collapsedHeight = 224;
  static const double _collapsedHeightWithBadge = 320;
  static const double _expandedWidth = 154;
  static const double _expandedHeight = 270;

  @override
  Widget build(BuildContext context) {
    final isLeft = edge == HomeRailEdge.left;
    final verticalLabel = label
        .toUpperCase()
        .split('')
        .where((character) => character.trim().isNotEmpty)
        .join('\n');
    final animationDuration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 280);

    return Semantics(
      button: true,
      label: label,
      child: Material(
        color: Colors.transparent,
        child: AnimatedContainer(
          duration: animationDuration,
          curve: Curves.easeOutCubic,
          width: expanded ? _expandedWidth : _collapsedWidth,
          height: expanded
              ? _expandedHeight
              : badge == null
              ? _collapsedHeight
              : _collapsedHeightWithBadge,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: <Color>[color.withValues(alpha: 0.92), color],
            ),
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(isLeft ? 0 : 24),
              bottomLeft: Radius.circular(isLeft ? 0 : 24),
              topRight: Radius.circular(isLeft ? 24 : 0),
              bottomRight: Radius.circular(isLeft ? 24 : 0),
            ),
            border: Border.all(color: Colors.white.withValues(alpha: 0.7)),
            boxShadow: const <BoxShadow>[
              BoxShadow(
                color: Color(0x32142451),
                blurRadius: 18,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onPressed,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(isLeft ? 0 : 24),
                bottomLeft: Radius.circular(isLeft ? 0 : 24),
                topRight: Radius.circular(isLeft ? 24 : 0),
                bottomRight: Radius.circular(isLeft ? 24 : 0),
              ),
              child: AnimatedSwitcher(
                duration: animationDuration,
                switchInCurve: Curves.easeOut,
                switchOutCurve: Curves.easeIn,
                child: expanded
                    ? _ExpandedRailContent(label: label, icon: icon)
                    : _CollapsedRailContent(
                        verticalLabel: verticalLabel,
                        icon: icon,
                        color: color,
                        badge: badge,
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ExpandedRailContent extends StatelessWidget {
  const _ExpandedRailContent({required this.label, required this.icon});

  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Center(
      key: const Key('expanded-home-mode-rail'),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, color: Colors.white, size: 36),
          const SizedBox(height: 14),
          Text(
            label,
            maxLines: 1,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 19,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _CollapsedRailContent extends StatelessWidget {
  const _CollapsedRailContent({
    required this.verticalLabel,
    required this.icon,
    required this.color,
    required this.badge,
  });

  final String verticalLabel;
  final IconData icon;
  final Color color;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    return Padding(
      key: const Key('collapsed-home-mode-rail'),
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(
        children: <Widget>[
          Icon(icon, color: Colors.white, size: 28),
          const SizedBox(height: 12),
          Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                verticalLabel,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  height: 1.05,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
          if (badge != null) ...<Widget>[
            const SizedBox(height: 8),
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 3),
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.92),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                badge!,
                maxLines: 2,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: color,
                  fontSize: 8.5,
                  height: 1.05,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
