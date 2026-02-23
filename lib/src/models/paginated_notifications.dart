import 'database_notification.dart';

/// Paginated wrapper for database notifications.
///
/// Maps the Laravel paginated response:
/// ```json
/// {
///   "data": [...],
///   "meta": { "current_page": 1, "last_page": 3, "per_page": 15, "total": 42 }
/// }
/// ```
class PaginatedNotifications {
  final List<DatabaseNotification> data;
  final int currentPage;
  final int lastPage;
  final int perPage;
  final int total;

  const PaginatedNotifications({
    required this.data,
    required this.currentPage,
    required this.lastPage,
    required this.perPage,
    required this.total,
  });

  /// Parse from API response map.
  factory PaginatedNotifications.fromMap(Map<String, dynamic> map) {
    final items = (map['data'] as List? ?? [])
        .map((e) => DatabaseNotification.fromMap(e as Map<String, dynamic>))
        .toList();

    final meta = map['meta'] as Map<String, dynamic>? ?? {};

    return PaginatedNotifications(
      data: items,
      currentPage: (meta['current_page'] as num?)?.toInt() ?? 1,
      lastPage: (meta['last_page'] as num?)?.toInt() ?? 1,
      perPage: (meta['per_page'] as num?)?.toInt() ?? 15,
      total: (meta['total'] as num?)?.toInt() ?? 0,
    );
  }

  bool get hasMorePages => currentPage < lastPage;
  bool get hasNextPage => currentPage < lastPage;
  bool get hasPreviousPage => currentPage > 1;

  /// Create an empty paginated response.
  factory PaginatedNotifications.empty() {
    return const PaginatedNotifications(
      data: [],
      currentPage: 1,
      lastPage: 1,
      perPage: 15,
      total: 0,
    );
  }
  bool get isEmpty => data.isEmpty;
}
