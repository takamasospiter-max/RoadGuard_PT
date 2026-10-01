import 'package:flutter/material.dart';
import 'package:roadguard_ai/core/services/road_api.dart';
import 'package:roadguard_ai/modules/home/presentation/pages/live_services_screens.dart';

/// Choose route keeps the selected Explore search result all the way through
/// to the live route preview. This screen intentionally has no demo fallback.
class PlannerScreen extends StatelessWidget {
  const PlannerScreen({super.key, this.destination});

  final PlaceResult? destination;

  @override
  Widget build(BuildContext context) =>
      LivePlannerScreen(destination: destination);
}
