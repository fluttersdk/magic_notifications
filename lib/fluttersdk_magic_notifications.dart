/// Multi-channel notification system for Magic Framework
///
/// Provides database (in-app), push (OneSignal), and mail notification channels.
library;

// ========================================
// Core
// ========================================
export 'src/notification_manager.dart';
export 'src/notification_poller.dart';

// ========================================
// Contracts
// ========================================
export 'src/contracts/channel.dart';
export 'src/contracts/notification.dart';
export 'src/contracts/notifiable.dart';

// ========================================
// Facades
// ========================================
export 'src/facades/notify.dart';

// ========================================
// Providers
// ========================================
export 'src/providers/notification_service_provider.dart';

// ========================================
// Exceptions
// ========================================
export 'src/exceptions/notification_exception.dart';

// ========================================
// Channels
// ========================================
export 'src/channels/database_channel.dart';
export 'src/channels/push_channel.dart';

// ========================================
// Models
// ========================================
export 'src/models/database_notification.dart';
export 'src/models/notification_preference.dart';
export 'src/models/push_message.dart';
export 'src/models/push_subscription.dart';

// ========================================
// Drivers
// ========================================
export 'src/drivers/push/push_driver.dart';
export 'src/drivers/push/onesignal_driver.dart';
export 'src/drivers/push/onesignal_web_driver.dart';
export 'src/drivers/push_web/onesignal_factory.dart';

// ========================================
// Widgets
// ========================================
export 'src/widgets/push_prompt_dialog.dart';
