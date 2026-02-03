/// A push notification message with fluent builder pattern.
///
/// Example:
/// ```dart
/// final message = PushMessage()
///   ..heading('Monitor Down')
///   ..content('api.example.com is not responding')
///   ..data({'monitor_id': '123'})
///   ..url('/monitors/123');
/// ```
class PushMessage {
  String? _heading;
  String? _content;
  Map<String, dynamic>? _data;
  String? _url;

  /// Sets the notification heading (title).
  PushMessage heading(String value) {
    _heading = value;
    return this;
  }

  /// Sets the notification content (body).
  PushMessage content(String value) {
    _content = value;
    return this;
  }

  /// Sets the notification data payload.
  PushMessage data(Map<String, dynamic> value) {
    _data = value;
    return this;
  }

  /// Sets the notification URL (deep link or action URL).
  PushMessage url(String value) {
    _url = value;
    return this;
  }

  /// Adds a single key-value pair to the data payload.
  /// Creates the data map if it doesn't exist.
  PushMessage addData(String key, dynamic value) {
    _data ??= {};
    _data![key] = value;
    return this;
  }

  /// Gets the heading value.
  String? get headingValue => _heading;

  /// Gets the content value.
  String? get contentValue => _content;

  /// Gets the data value.
  Map<String, dynamic>? get dataValue => _data;

  /// Gets the URL value.
  String? get urlValue => _url;

  /// Converts the message to a Map, excluding null values.
  Map<String, dynamic> toMap() {
    final map = <String, dynamic>{};

    if (_heading != null) {
      map['heading'] = _heading;
    }
    if (_content != null) {
      map['content'] = _content;
    }
    if (_data != null) {
      map['data'] = _data;
    }
    if (_url != null) {
      map['url'] = _url;
    }

    return map;
  }
}
