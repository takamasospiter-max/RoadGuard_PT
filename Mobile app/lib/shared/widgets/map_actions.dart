import 'package:flutter/material.dart';
import 'package:roadguard_ai/core/theme/app_theme.dart';

/// Compact map controls retain spoken labels and 48 dp touch targets.
class MapActionButtons extends StatelessWidget {
  const MapActionButtons({
    super.key,
    required this.onLocate,
    required this.onDirections,
    required this.onReport,
    this.onResume,
    this.locationActive = false,
  });
  final VoidCallback? onLocate, onResume;
  final VoidCallback onDirections;
  final VoidCallback onReport;
  final bool locationActive;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    Widget action(
      Key key,
      String label,
      IconData icon,
      VoidCallback? onTap, {
      bool primary = false,
    }) => Material(
      elevation: 4,
      color: primary ? colors.primary : colors.surface,
      shape: const CircleBorder(),
      child: SizedBox.square(
        dimension: 48,
        child: IconButton(
          key: key,
          tooltip: label,
          onPressed: onTap,
          icon: Icon(
            icon,
            color: onTap == null
                ? colors.onSurfaceVariant
                : primary
                ? colors.onPrimary
                : colors.primary,
          ),
        ),
      ),
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        action(
          const Key('map-my-location'),
          locationActive ? 'Stop location' : 'My location',
          locationActive ? Icons.gps_fixed : Icons.my_location,
          onLocate,
        ),
        const SizedBox(height: 12),
        action(
          const Key('map-directions'),
          'Directions',
          Icons.directions_rounded,
          onDirections,
          primary: true,
        ),
        const SizedBox(height: 12),
        action(
          const Key('map-report-hazard'),
          'Report hazard',
          Icons.add_location_alt_outlined,
          onReport,
        ),
        if (onResume != null) ...[
          const SizedBox(height: 12),
          action(
            const Key('map-resume-trip'),
            'Resume trip',
            Icons.navigation_rounded,
            onResume,
          ),
        ],
      ],
    );
  }
}

class MapSearchBar extends StatelessWidget {
  const MapSearchBar({
    super.key,
    required this.onTap,
    this.actionKey,
    this.controller,
    this.readOnly = true,
    this.autofocus = false,
    this.onChanged,
    this.onSubmitted,
  });
  final VoidCallback onTap;
  final Key? actionKey;
  final TextEditingController? controller;
  final bool readOnly, autofocus;
  final ValueChanged<String>? onChanged, onSubmitted;
  @override
  Widget build(BuildContext context) => Material(
    elevation: 4,
    borderRadius: BorderRadius.circular(28),
    child: TextField(
      key: actionKey,
      controller: controller,
      readOnly: readOnly,
      autofocus: autofocus,
      textInputAction: TextInputAction.search,
      onTap: readOnly ? onTap : null,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      decoration: InputDecoration(
        hintText: 'Search here',
        hintStyle: const TextStyle(color: Color(0xFF355568), fontSize: 16),
        prefixIcon: const Icon(Icons.circle, size: 11, color: RoadColors.blue),
        filled: true,
        fillColor: Theme.of(context).colorScheme.surface,
        contentPadding: const EdgeInsets.symmetric(vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(28),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(28),
          borderSide: BorderSide.none,
        ),
      ),
    ),
  );
}
