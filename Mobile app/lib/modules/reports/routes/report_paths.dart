abstract final class ReportPaths {
  static const reports = '/reports';
  static const create = '/report';
  static const detail = '/reports/:id';

  static String reportDetail(String id) =>
      '/reports/${Uri.encodeComponent(id)}';
}
