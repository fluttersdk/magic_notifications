library magic_notifications;

// Contracts
export 'src/contracts/notification.dart';
export 'src/contracts/channel.dart';
export 'src/contracts/notifiable.dart';

// Models
export 'src/models/database_notification.dart';
export 'src/models/notification_preference.dart';
export 'src/models/paginated_notifications.dart';
export 'src/models/push_message.dart';
export 'src/models/push_subscription.dart';

// Core
export 'src/notification_manager.dart';
export 'src/notification_poller.dart';

// Facade
export 'src/facades/notify.dart';

// Channels
export 'src/channels/database_channel.dart';
export 'src/channels/push_channel.dart';

// Providers
export 'src/providers/notification_service_provider.dart';

// Drivers
export 'src/drivers/push/push_driver.dart';
export 'src/drivers/push/onesignal_driver.dart';

// Widgets
export 'src/widgets/push_prompt_dialog.dart';

// Exceptions
export 'src/exceptions/notification_exception.dart';
