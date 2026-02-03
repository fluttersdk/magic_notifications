// ignore_for_file: avoid_web_libraries_in_flutter

import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

/// Web implementation of OneSignal JavaScript SDK interop.
///
/// Uses dart:js_interop to communicate with the OneSignal Web SDK v16.
/// The SDK must be loaded via script tag in index.html for this to work.

/// Initialize OneSignal with configuration.
///
/// This should be called once during app startup. Config options:
/// - `appId` (required): Your OneSignal App ID
/// - `safariWebId` (optional): Safari Web ID for Safari browser support
/// - `notifyButtonEnabled` (optional): Show floating bell widget (default: false)
Future<void> init({
  required String appId,
  String? safariWebId,
  bool notifyButtonEnabled = false,
}) async {
  // Build the init config object
  final initConfig = JSObject();
  initConfig['appId'] = appId.toJS;

  if (safariWebId != null && safariWebId.isNotEmpty) {
    initConfig['safari_web_id'] = safariWebId.toJS;
  }

  // NotifyButton config
  final notifyButton = JSObject();
  notifyButton['enable'] = notifyButtonEnabled.toJS;
  initConfig['notifyButton'] = notifyButton;

  // Push the init call to OneSignalDeferred
  final oneSignalDeferred = globalContext['OneSignalDeferred'] as JSArray?;
  if (oneSignalDeferred != null) {
    // Create callback function that will be called with OneSignal object
    void initCallback(JSObject oneSignal) {
      oneSignal.callMethod('init'.toJS, initConfig);
    }

    oneSignalDeferred.callMethod('push'.toJS, initCallback.toJS);
  }

  // Wait a bit for init to complete
  await Future.delayed(const Duration(milliseconds: 500));
}

/// Whether the OneSignal SDK is available and initialized.
bool get isAvailable {
  try {
    final oneSignal = globalContext['OneSignal'];
    if (oneSignal == null || oneSignal.isUndefinedOrNull) return false;

    // Check if it's the actual SDK (not just the deferred array)
    // The SDK replaces the deferred array with the real object after init
    final jsObj = oneSignal as JSObject;
    final loginFn = jsObj['login'];
    return loginFn != null && !loginFn.isUndefinedOrNull;
  } catch (e) {
    return false;
  }
}

/// Gets the OneSignal object, throwing if not available.
JSObject _getOneSignal() {
  final oneSignal = globalContext['OneSignal'] as JSObject?;
  if (oneSignal == null) {
    throw Exception(
        'OneSignal SDK not available. Make sure the script is loaded.');
  }
  return oneSignal;
}

/// Sets the external user ID to identify the user.
Future<void> login(String externalId) async {
  final oneSignal = _getOneSignal();
  final result = oneSignal.callMethod('login'.toJS, externalId.toJS);
  if (result != null && !result.isUndefinedOrNull) {
    await (result as JSPromise).toDart;
  }
}

/// Removes the external user ID from the current subscription.
Future<void> logout() async {
  final oneSignal = _getOneSignal();
  final result = oneSignal.callMethod('logout'.toJS);
  if (result != null && !result.isUndefinedOrNull) {
    await (result as JSPromise).toDart;
  }
}

/// Requests push notification permission from the browser.
Future<bool> requestPermission() async {
  final oneSignal = _getOneSignal();
  final notifications = oneSignal['Notifications'] as JSObject?;
  if (notifications != null) {
    final result = notifications.callMethod('requestPermission'.toJS);
    if (result != null && !result.isUndefinedOrNull) {
      await (result as JSPromise).toDart;
    }
    return getPermission();
  }
  return false;
}

/// Opts the user in to push notifications.
Future<void> optIn() async {
  final oneSignal = _getOneSignal();
  final user = oneSignal['User'] as JSObject?;
  if (user != null) {
    final pushSubscription = user['PushSubscription'] as JSObject?;
    if (pushSubscription != null) {
      final result = pushSubscription.callMethod('optIn'.toJS);
      if (result != null && !result.isUndefinedOrNull) {
        await (result as JSPromise).toDart;
      }
    }
  }
}

/// Opts the user out of push notifications.
Future<void> optOut() async {
  final oneSignal = _getOneSignal();
  final user = oneSignal['User'] as JSObject?;
  if (user != null) {
    final pushSubscription = user['PushSubscription'] as JSObject?;
    if (pushSubscription != null) {
      final result = pushSubscription.callMethod('optOut'.toJS);
      if (result != null && !result.isUndefinedOrNull) {
        await (result as JSPromise).toDart;
      }
    }
  }
}

/// Adds tags to the user for segmentation.
Future<void> addTags(Map<String, String> tags) async {
  final oneSignal = _getOneSignal();
  final user = oneSignal['User'] as JSObject?;
  if (user != null) {
    // Convert Map to JSObject
    final jsObj = JSObject();
    for (final entry in tags.entries) {
      jsObj[entry.key] = entry.value.toJS;
    }
    user.callMethod('addTags'.toJS, jsObj);
  }
}

/// Removes a single tag from the user.
Future<void> removeTag(String key) async {
  final oneSignal = _getOneSignal();
  final user = oneSignal['User'] as JSObject?;
  if (user != null) {
    user.callMethod('removeTag'.toJS, key.toJS);
  }
}

/// Removes multiple tags from the user.
Future<void> removeTags(List<String> keys) async {
  final oneSignal = _getOneSignal();
  final user = oneSignal['User'] as JSObject?;
  if (user != null) {
    final jsArray = keys.map((k) => k.toJS).toList().toJS;
    user.callMethod('removeTags'.toJS, jsArray);
  }
}

/// Gets the current push permission state.
bool getPermission() {
  try {
    final oneSignal = globalContext['OneSignal'] as JSObject?;
    if (oneSignal != null) {
      final notifications = oneSignal['Notifications'] as JSObject?;
      if (notifications != null) {
        final permission = notifications['permission'];
        if (permission != null && !permission.isUndefinedOrNull) {
          return (permission as JSBoolean).toDart;
        }
      }
    }
  } catch (e) {
    // Ignore errors
  }
  return false;
}

/// Gets the current opt-in state.
bool getOptedIn() {
  try {
    final oneSignal = globalContext['OneSignal'] as JSObject?;
    if (oneSignal != null) {
      final user = oneSignal['User'] as JSObject?;
      if (user != null) {
        final pushSubscription = user['PushSubscription'] as JSObject?;
        if (pushSubscription != null) {
          final optedIn = pushSubscription['optedIn'];
          if (optedIn != null && !optedIn.isUndefinedOrNull) {
            return (optedIn as JSBoolean).toDart;
          }
        }
      }
    }
  } catch (e) {
    // Ignore errors
  }
  return false;
}

/// Gets the current external user ID.
String? getExternalId() {
  try {
    final oneSignal = globalContext['OneSignal'] as JSObject?;
    if (oneSignal != null) {
      final user = oneSignal['User'] as JSObject?;
      if (user != null) {
        final externalId = user['externalId'];
        if (externalId != null && !externalId.isUndefinedOrNull) {
          return (externalId as JSString).toDart;
        }
      }
    }
  } catch (e) {
    // Ignore errors
  }
  return null;
}

/// Gets the current subscription ID.
String? getSubscriptionId() {
  try {
    final oneSignal = globalContext['OneSignal'] as JSObject?;
    if (oneSignal != null) {
      final user = oneSignal['User'] as JSObject?;
      if (user != null) {
        final pushSubscription = user['PushSubscription'] as JSObject?;
        if (pushSubscription != null) {
          final id = pushSubscription['id'];
          if (id != null && !id.isUndefinedOrNull) {
            return (id as JSString).toDart;
          }
        }
      }
    }
  } catch (e) {
    // Ignore errors
  }
  return null;
}

/// Gets the OneSignal user ID.
String? getOneSignalId() {
  try {
    final oneSignal = globalContext['OneSignal'] as JSObject?;
    if (oneSignal != null) {
      final user = oneSignal['User'] as JSObject?;
      if (user != null) {
        final onesignalId = user['onesignalId'];
        if (onesignalId != null && !onesignalId.isUndefinedOrNull) {
          return (onesignalId as JSString).toDart;
        }
      }
    }
  } catch (e) {
    // Ignore errors
  }
  return null;
}

/// Gets all tags for the current user.
Map<String, String>? getTags() {
  try {
    final oneSignal = globalContext['OneSignal'] as JSObject?;
    if (oneSignal != null) {
      final user = oneSignal['User'] as JSObject?;
      if (user != null) {
        final result = user.callMethod('getTags'.toJS);
        if (result != null && !result.isUndefinedOrNull) {
          // Convert JSObject to Map
          final jsObj = result as JSObject;
          final keys = _getObjectKeys(jsObj);
          final map = <String, String>{};
          for (final key in keys) {
            final value = jsObj[key];
            if (value != null && !value.isUndefinedOrNull) {
              map[key] = (value as JSString).toDart;
            }
          }
          return map;
        }
      }
    }
  } catch (e) {
    // Ignore errors
  }
  return null;
}

/// Sets the language for the current user.
Future<void> setLanguage(String languageCode) async {
  final oneSignal = _getOneSignal();
  final user = oneSignal['User'] as JSObject?;
  if (user != null) {
    user.callMethod('setLanguage'.toJS, languageCode.toJS);
  }
}

/// Sets the log level for debugging.
void setLogLevel(String level) {
  try {
    final oneSignal = globalContext['OneSignal'] as JSObject?;
    if (oneSignal != null) {
      final debug = oneSignal['Debug'] as JSObject?;
      if (debug != null) {
        debug.callMethod('setLogLevel'.toJS, level.toJS);
      }
    }
  } catch (e) {
    // Ignore errors
  }
}

/// Displays the push notification slidedown prompt.
Future<void> promptPush({bool force = false}) async {
  final oneSignal = _getOneSignal();
  final slidedown = oneSignal['Slidedown'] as JSObject?;
  if (slidedown != null) {
    JSAny? result;
    if (force) {
      final options = JSObject();
      options['force'] = true.toJS;
      result = slidedown.callMethod('promptPush'.toJS, options);
    } else {
      result = slidedown.callMethod('promptPush'.toJS);
    }
    if (result != null && !result.isUndefinedOrNull) {
      await (result as JSPromise).toDart;
    }
  }
}

/// Displays the category slidedown prompt.
Future<void> promptPushCategories({bool force = false}) async {
  final oneSignal = _getOneSignal();
  final slidedown = oneSignal['Slidedown'] as JSObject?;
  if (slidedown != null) {
    JSAny? result;
    if (force) {
      final options = JSObject();
      options['force'] = true.toJS;
      result = slidedown.callMethod('promptPushCategories'.toJS, options);
    } else {
      result = slidedown.callMethod('promptPushCategories'.toJS);
    }
    if (result != null && !result.isUndefinedOrNull) {
      await (result as JSPromise).toDart;
    }
  }
}

/// Adds a listener for permission state changes.
void addPermissionChangeListener(void Function(bool permission) callback) {
  try {
    final oneSignal = globalContext['OneSignal'] as JSObject?;
    if (oneSignal != null) {
      final notifications = oneSignal['Notifications'] as JSObject?;
      if (notifications != null) {
        void jsCallback(JSBoolean permission) {
          callback(permission.toDart);
        }

        notifications.callMethod(
          'addEventListener'.toJS,
          'permissionChange'.toJS,
          jsCallback.toJS,
        );
      }
    }
  } catch (e) {
    // Ignore errors
  }
}

/// Adds a listener for notification click events.
void addNotificationClickListener(
  void Function(Map<String, dynamic> event) callback,
) {
  try {
    final oneSignal = globalContext['OneSignal'] as JSObject?;
    if (oneSignal != null) {
      final notifications = oneSignal['Notifications'] as JSObject?;
      if (notifications != null) {
        void jsCallback(JSObject event) {
          callback(_jsObjectToMap(event));
        }

        notifications.callMethod(
          'addEventListener'.toJS,
          'click'.toJS,
          jsCallback.toJS,
        );
      }
    }
  } catch (e) {
    // Ignore errors
  }
}

/// Adds a listener for foreground notification display events.
void addNotificationForegroundListener(
  void Function(Map<String, dynamic> event) callback,
) {
  try {
    final oneSignal = globalContext['OneSignal'] as JSObject?;
    if (oneSignal != null) {
      final notifications = oneSignal['Notifications'] as JSObject?;
      if (notifications != null) {
        void jsCallback(JSObject event) {
          callback(_jsObjectToMap(event));
        }

        notifications.callMethod(
          'addEventListener'.toJS,
          'foregroundWillDisplay'.toJS,
          jsCallback.toJS,
        );
      }
    }
  } catch (e) {
    // Ignore errors
  }
}

/// Adds a listener for user state changes.
void addUserStateChangeListener(
  void Function(Map<String, dynamic> event) callback,
) {
  try {
    final oneSignal = globalContext['OneSignal'] as JSObject?;
    if (oneSignal != null) {
      final user = oneSignal['User'] as JSObject?;
      if (user != null) {
        void jsCallback(JSObject event) {
          callback(_jsObjectToMap(event));
        }

        user.callMethod(
          'addEventListener'.toJS,
          'change'.toJS,
          jsCallback.toJS,
        );
      }
    }
  } catch (e) {
    // Ignore errors
  }
}

/// Adds a listener for subscription state changes.
void addSubscriptionChangeListener(
  void Function(Map<String, dynamic> event) callback,
) {
  try {
    final oneSignal = globalContext['OneSignal'] as JSObject?;
    if (oneSignal != null) {
      final user = oneSignal['User'] as JSObject?;
      if (user != null) {
        final pushSubscription = user['PushSubscription'] as JSObject?;
        if (pushSubscription != null) {
          void jsCallback(JSObject event) {
            callback(_jsObjectToMap(event));
          }

          pushSubscription.callMethod(
            'addEventListener'.toJS,
            'change'.toJS,
            jsCallback.toJS,
          );
        }
      }
    }
  } catch (e) {
    // Ignore errors
  }
}

/// Helper to get object keys from a JSObject.
List<String> _getObjectKeys(JSObject obj) {
  try {
    final objectConstructor = globalContext['Object'] as JSObject;
    final result = objectConstructor.callMethod('keys'.toJS, obj) as JSArray;

    final keys = <String>[];
    for (var i = 0; i < result.length; i++) {
      final key = result[i];
      if (key != null && !key.isUndefinedOrNull) {
        keys.add((key as JSString).toDart);
      }
    }
    return keys;
  } catch (e) {
    return [];
  }
}

/// Helper to convert a JSObject to a Map.
Map<String, dynamic> _jsObjectToMap(JSObject obj) {
  final map = <String, dynamic>{};
  try {
    final keys = _getObjectKeys(obj);
    for (final key in keys) {
      final value = obj[key];
      if (value != null && !value.isUndefinedOrNull) {
        map[key] = _jsValueToDart(value);
      }
    }
  } catch (e) {
    // Ignore errors
  }
  return map;
}

/// Helper to convert a JS value to a Dart value.
dynamic _jsValueToDart(JSAny? value) {
  if (value == null || value.isUndefinedOrNull) {
    return null;
  }

  // Try different JS types using typeofEquals for SDK compatibility
  try {
    final typeOf = value.typeofEquals('string');
    if (typeOf) {
      return (value as JSString).toDart;
    }
  } catch (_) {}

  try {
    final typeOf = value.typeofEquals('number');
    if (typeOf) {
      return (value as JSNumber).toDartDouble;
    }
  } catch (_) {}

  try {
    final typeOf = value.typeofEquals('boolean');
    if (typeOf) {
      return (value as JSBoolean).toDart;
    }
  } catch (_) {}

  // Check for array (typeof returns 'object' for arrays)
  try {
    final isArray = _jsIsArray(value);
    if (isArray) {
      final arr = value as JSArray;
      final list = <dynamic>[];
      for (var i = 0; i < arr.length; i++) {
        list.add(_jsValueToDart(arr[i]));
      }
      return list;
    }
  } catch (_) {}

  // Try as object
  try {
    final typeOf = value.typeofEquals('object');
    if (typeOf) {
      return _jsObjectToMap(value as JSObject);
    }
  } catch (_) {}

  // Fallback: return as string
  return value.toString();
}

/// Helper to check if a JS value is an array.
bool _jsIsArray(JSAny? value) {
  try {
    final arrayConstructor = globalContext['Array'] as JSObject;
    final result = arrayConstructor.callMethod('isArray'.toJS, value);
    if (result != null && !result.isUndefinedOrNull) {
      return (result as JSBoolean).toDart;
    }
  } catch (_) {}
  return false;
}
