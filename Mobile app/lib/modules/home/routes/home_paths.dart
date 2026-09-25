abstract final class HomePaths {
  static const explore = '/explore';
  static const alerts = '/alerts';
  static const hazards = '/hazards';
  static const hazard = '/hazard/:id';

  static String hazardDetail(String id) => '/hazard/${Uri.encodeComponent(id)}';
}
