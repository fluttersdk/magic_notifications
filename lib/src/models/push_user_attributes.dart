import 'package:flutter/foundation.dart' show immutable, mapEquals;

/// Answers what the push platform should be told about the person a device is
/// subscribed as.
///
/// Called with the external id the device is being subscribed as, which is the
/// same string the host passed to `Notify.initializePush()`, so a host that
/// keeps its user state elsewhere can look the right person up rather than
/// having to remember which login this is. Returning `null` says there is
/// nothing to describe for that identity, which is exactly what a host answers
/// for a guest, a service account, or a person who has not consented.
///
/// Synchronous on purpose. It is invoked from the identity reconcile pass, and
/// the guarantee that pass exists for is that the device stops carrying the
/// previous person as fast as possible; a resolver that awaited a network read
/// would hold the login, and with it every promise that depends on the device
/// carrying the right subject, behind a request that may never answer. Read
/// from state the app already has.
typedef PushUserAttributesResolver = PushUserAttributes? Function(
  String externalId,
);

/// **What the push platform is told about the person on this device.**
///
/// This package owns the transport and the identity lifecycle; the HOST owns
/// the values. "Email, first name, last name" is one product's answer, and the
/// next app either has different fields or is not permitted to send an email
/// address at all, so there is no fixed field list here to fill in: a host
/// describes whoever is signing in through
/// `NotificationManager.describePushUserUsing`, once, and the identity
/// lifecycle applies it on every login and takes it back on every switch.
///
/// ### Example Usage:
///
/// ```dart
/// Notify.describePushUserUsing((String externalId) {
///   final user = Auth.user();
///   if (user == null) return null;
///
///   return PushUserAttributes(
///     email: user.email,
///     tags: <String, String>{
///       'first_name': user.firstName,
///       'last_name': user.lastName,
///       'locale': user.locale,
///     },
///   );
/// });
/// ```
///
/// Nothing here is sent unless the deployment switched
/// `notifications.push.share_user_attributes` on. It ships off, because an
/// address and a name reaching a third party is a decision an adopter makes,
/// not one they discover in a vendor dashboard months later.
///
/// ### What is deliberately absent
///
/// The OneSignal user model also carries SMS subscriptions, aliases and a
/// language. None of them was asked for, and each would be a field here plus a
/// pair of methods on `PushDriver`: they are absent because nothing needs them
/// yet, not because they cannot be carried.
@immutable
class PushUserAttributes {
  /// The address the platform may reach this person on, or `null` for none.
  ///
  /// **This is personal data leaving the app for a third party.** It is what
  /// `notifications.push.share_user_attributes` exists to gate, and why that
  /// key ships off.
  ///
  /// It is ATTACHED rather than set, because that is what both SDKs do: a
  /// OneSignal user owns zero or more email subscriptions. What makes it read
  /// as "the address for this identity" is the manager, which detaches the
  /// address it previously attached whenever the described one changes and
  /// takes it back entirely when the identity does.
  final String? email;

  /// The key/value pairs the platform segments and personalises on.
  ///
  /// A name has no field of its own in the OneSignal user model, so a first or
  /// last name travels here, as a tag the host names.
  ///
  /// **A tag written from a client is user-tamperable.** Anybody holding the
  /// app can call the SDK from a browser console and write whatever they like
  /// under any key, so a tag is safe for choosing an audience and safe for
  /// personalising a message, and it is NOT safe for anything a backend later
  /// trusts. A plan tier, an entitlement, a role, a quota: those decide what
  /// somebody is allowed, and a value the person being checked can rewrite
  /// decides nothing. They belong in a server-side tag write over OneSignal's
  /// REST API, from the system that already owns the fact. This package ships
  /// no such path and will not: it has no server credentials and no business
  /// holding any.
  final Map<String, String> tags;

  /// Describes one person for the push platform.
  ///
  /// [tags] is treated as owned by this object; mutating the map after
  /// construction leaves the manager comparing against a value that has
  /// changed underneath it.
  const PushUserAttributes({
    this.email,
    this.tags = const <String, String>{},
  });

  /// Nothing to say about this person.
  ///
  /// The answer for a host that registered no resolver, a resolver that
  /// answered `null`, and a deployment that has not opted in, so those three
  /// travel the same path rather than each getting a null check of its own.
  static const PushUserAttributes none = PushUserAttributes();

  /// Whether there is nothing here to send.
  bool get isEmpty => email == null && tags.isEmpty;

  /// Whether there is anything here to send.
  bool get isNotEmpty => !isEmpty;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is PushUserAttributes &&
        other.email == email &&
        mapEquals(other.tags, tags);
  }

  @override
  int get hashCode {
    // Unordered, because two maps carrying the same pairs describe the same
    // person whatever order they were built in, and the equality above already
    // reads them that way.
    return Object.hash(
      email,
      Object.hashAllUnordered(
        tags.entries.map((MapEntry<String, String> tag) {
          return Object.hash(tag.key, tag.value);
        }),
      ),
    );
  }

  @override
  String toString() {
    return 'PushUserAttributes(email: $email, tags: $tags)';
  }
}
