# Laravel Backend Setup Guide

This guide shows how to implement the notification backend using Laravel's built-in notification system.

## Prerequisites

- Laravel 10.x or higher
- PHP 8.1+
- Composer

## 1. Create Notifications Table

Laravel provides a built-in artisan command to create the notifications table:

```bash
php artisan make:notifications-table
php artisan migrate
```

This creates the standard `notifications` table with the following structure:

| Column | Type | Description |
|--------|------|-------------|
| id | uuid | Primary key |
| type | string | Notification class name |
| notifiable_type | string | Model type (e.g., App\Models\User) |
| notifiable_id | bigint | Model ID |
| data | json | Notification payload |
| read_at | timestamp | When marked as read (null = unread) |
| created_at | timestamp | Creation time |
| updated_at | timestamp | Last update time |

## 2. Create Notification Preferences Table

```bash
php artisan make:migration create_notification_preferences_table
```

Edit the migration:

```php
<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('notification_preferences', function (Blueprint $table) {
            $table->id();
            $table->foreignId('user_id')->constrained()->onDelete('cascade');
            $table->boolean('push_enabled')->default(true);
            $table->boolean('email_enabled')->default(true);
            $table->boolean('in_app_enabled')->default(true);
            $table->json('type_preferences')->nullable();
            $table->timestamps();

            $table->unique('user_id');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('notification_preferences');
    }
};
```

Run the migration:

```bash
php artisan migrate
```

## 3. Setup User Model

Ensure your User model uses the `Notifiable` trait:

```php
<?php

namespace App\Models;

use Illuminate\Foundation\Auth\User as Authenticatable;
use Illuminate\Notifications\Notifiable;

class User extends Authenticatable
{
    use Notifiable;

    public function notificationPreference()
    {
        return $this->hasOne(NotificationPreference::class);
    }
}
```

## 4. Create NotificationPreference Model

```bash
php artisan make:model NotificationPreference
```

```php
<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class NotificationPreference extends Model
{
    protected $fillable = [
        'user_id',
        'push_enabled',
        'email_enabled',
        'in_app_enabled',
        'type_preferences',
    ];

    protected $casts = [
        'push_enabled' => 'boolean',
        'email_enabled' => 'boolean',
        'in_app_enabled' => 'boolean',
        'type_preferences' => 'array',
    ];

    public function user(): BelongsTo
    {
        return $this->belongsTo(User::class);
    }
}
```

## 5. Create a Notification Class

```bash
php artisan make:notification MonitorDownNotification
```

```php
<?php

namespace App\Notifications;

use App\Models\Monitor;
use Illuminate\Bus\Queueable;
use Illuminate\Notifications\Notification;
use Illuminate\Notifications\Messages\MailMessage;

class MonitorDownNotification extends Notification
{
    use Queueable;

    public function __construct(
        public Monitor $monitor
    ) {}

    /**
     * Determine which channels the notification should be delivered on.
     *
     * @return array<int, string>
     */
    public function via(object $notifiable): array
    {
        $channels = [];
        $prefs = $notifiable->notificationPreference;

        if (!$prefs || $prefs->in_app_enabled) {
            $channels[] = 'database';
        }

        if (!$prefs || $prefs->email_enabled) {
            $channels[] = 'mail';
        }

        return $channels;
    }

    /**
     * Get the array representation for database storage.
     *
     * @return array<string, mixed>
     */
    public function toArray(object $notifiable): array
    {
        return [
            'title' => 'Monitor Down',
            'body' => "Your monitor '{$this->monitor->name}' is not responding.",
            'action_url' => "/monitors/{$this->monitor->id}",
            'monitor_id' => $this->monitor->id,
        ];
    }

    /**
     * Customize the notification type stored in database.
     */
    public function databaseType(object $notifiable): string
    {
        return 'monitor_down';
    }

    /**
     * Get the mail representation of the notification.
     */
    public function toMail(object $notifiable): MailMessage
    {
        return (new MailMessage)
            ->subject('Monitor Alert: ' . $this->monitor->name)
            ->greeting('Hello!')
            ->line("Your monitor '{$this->monitor->name}' is currently down.")
            ->action('View Monitor', url("/monitors/{$this->monitor->id}"))
            ->line('We will notify you when it recovers.');
    }
}
```

## 6. Create API Controllers

### NotificationController

```bash
php artisan make:controller Api/V1/NotificationController
```

```php
<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use Illuminate\Http\Request;
use Illuminate\Http\JsonResponse;

class NotificationController extends Controller
{
    /**
     * List user notifications.
     */
    public function index(Request $request): JsonResponse
    {
        $notifications = $request->user()
            ->notifications()
            ->paginate($request->input('per_page', 15));

        return response()->json([
            'data' => $notifications->map(fn ($n) => [
                'id' => $n->id,
                'type' => $n->type,
                'data' => $n->data,
                'read_at' => $n->read_at?->toIso8601String(),
                'created_at' => $n->created_at->toIso8601String(),
            ]),
            'meta' => [
                'current_page' => $notifications->currentPage(),
                'last_page' => $notifications->lastPage(),
                'per_page' => $notifications->perPage(),
                'total' => $notifications->total(),
            ],
        ]);
    }

    /**
     * Get unread notification count.
     */
    public function unreadCount(Request $request): JsonResponse
    {
        $count = $request->user()->unreadNotifications()->count();

        return response()->json(['count' => $count]);
    }

    /**
     * Mark a notification as read.
     */
    public function markAsRead(Request $request, string $id): JsonResponse
    {
        $notification = $request->user()
            ->notifications()
            ->findOrFail($id);

        $notification->markAsRead();

        return response()->json(['message' => 'Notification marked as read']);
    }

    /**
     * Mark all notifications as read.
     */
    public function markAllAsRead(Request $request): JsonResponse
    {
        $request->user()->unreadNotifications->markAsRead();

        return response()->json(['message' => 'All notifications marked as read']);
    }

    /**
     * Delete a notification.
     */
    public function destroy(Request $request, string $id): JsonResponse
    {
        $request->user()
            ->notifications()
            ->findOrFail($id)
            ->delete();

        return response()->json(['message' => 'Notification deleted']);
    }
}
```

### NotificationPreferenceController

```bash
php artisan make:controller Api/V1/NotificationPreferenceController
```

```php
<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Models\NotificationPreference;
use Illuminate\Http\Request;
use Illuminate\Http\JsonResponse;

class NotificationPreferenceController extends Controller
{
    /**
     * Get user's notification preferences.
     */
    public function show(Request $request): JsonResponse
    {
        $prefs = $request->user()->notificationPreference
            ?? NotificationPreference::create(['user_id' => $request->user()->id]);

        return response()->json([
            'data' => [
                'push_enabled' => $prefs->push_enabled,
                'email_enabled' => $prefs->email_enabled,
                'in_app_enabled' => $prefs->in_app_enabled,
                'type_preferences' => $prefs->type_preferences,
            ],
        ]);
    }

    /**
     * Update user's notification preferences.
     */
    public function update(Request $request): JsonResponse
    {
        $validated = $request->validate([
            'push_enabled' => 'sometimes|boolean',
            'email_enabled' => 'sometimes|boolean',
            'in_app_enabled' => 'sometimes|boolean',
            'type_preferences' => 'sometimes|array',
        ]);

        $prefs = $request->user()->notificationPreference
            ?? new NotificationPreference(['user_id' => $request->user()->id]);

        if (isset($validated['push_enabled'])) {
            $prefs->push_enabled = $validated['push_enabled'];
        }
        if (isset($validated['email_enabled'])) {
            $prefs->email_enabled = $validated['email_enabled'];
        }
        if (isset($validated['in_app_enabled'])) {
            $prefs->in_app_enabled = $validated['in_app_enabled'];
        }
        if (isset($validated['type_preferences'])) {
            $prefs->type_preferences = $validated['type_preferences'];
        }

        $prefs->save();

        return response()->json([
            'message' => 'Preferences updated',
            'data' => [
                'push_enabled' => $prefs->push_enabled,
                'email_enabled' => $prefs->email_enabled,
                'in_app_enabled' => $prefs->in_app_enabled,
                'type_preferences' => $prefs->type_preferences,
            ],
        ]);
    }
}
```

## 7. Add API Routes

In `routes/api/v1.php`:

```php
<?php

use App\Http\Controllers\Api\V1\NotificationController;
use App\Http\Controllers\Api\V1\NotificationPreferenceController;
use Illuminate\Support\Facades\Route;

Route::middleware('auth:sanctum')->group(function () {
    // Notifications
    Route::get('notifications', [NotificationController::class, 'index']);
    Route::get('notifications/unread-count', [NotificationController::class, 'unreadCount']);
    Route::post('notifications/{id}/read', [NotificationController::class, 'markAsRead']);
    Route::post('notifications/read-all', [NotificationController::class, 'markAllAsRead']);
    Route::delete('notifications/{id}', [NotificationController::class, 'destroy']);

    // Notification Preferences
    Route::get('notification-preferences', [NotificationPreferenceController::class, 'show']);
    Route::put('notification-preferences', [NotificationPreferenceController::class, 'update']);
});
```

## 8. OneSignal Push Notifications (Optional)

For push notifications via OneSignal:

### Install Packages

```bash
composer require laravel-notification-channels/onesignal
composer require berkayk/onesignal-laravel
```

### Publish OneSignal Config

```bash
php artisan vendor:publish --provider="Berkayk\OneSignal\OneSignalServiceProvider"
```

This creates `config/onesignal.php` which reads from environment variables.

### Configure Environment

Add to `.env`:

```env
ONESIGNAL_APP_ID=your-onesignal-app-id
ONESIGNAL_REST_API_KEY=your-onesignal-rest-api-key
```

> **Note**: Get the REST API Key from OneSignal Dashboard → Settings → Keys & IDs. Use the "REST API Key" (starts with `os_v2_app_...`), not the "User Auth Key".

### Update Notification Class

```php
<?php

namespace App\Notifications;

use App\Models\Monitor;
use Illuminate\Bus\Queueable;
use Illuminate\Notifications\Notification;
use NotificationChannels\OneSignal\OneSignalChannel;
use NotificationChannels\OneSignal\OneSignalMessage;

class MonitorDownNotification extends Notification
{
    use Queueable;

    public function __construct(
        public Monitor $monitor
    ) {}

    public function via(object $notifiable): array
    {
        $channels = ['database'];
        $prefs = $notifiable->notificationPreference;

        if (!$prefs || $prefs->push_enabled) {
            $channels[] = OneSignalChannel::class;
        }

        if (!$prefs || $prefs->email_enabled) {
            $channels[] = 'mail';
        }

        return $channels;
    }

    public function toOneSignal(object $notifiable): OneSignalMessage
    {
        return OneSignalMessage::create()
            ->setSubject('Monitor Down')
            ->setBody("Your monitor '{$this->monitor->name}' is not responding.")
            ->setUrl(url("/monitors/{$this->monitor->id}"))
            ->setData('monitor_id', $this->monitor->id);
    }

    // ... toArray and toMail methods remain the same
}
```

### Route User to OneSignal

Add to User model:

```php
/**
 * Route notifications for OneSignal channel.
 *
 * IMPORTANT: The external_user_id must match what the Flutter app sets
 * when calling Notify.initializePush('user_' + user.id).
 *
 * We use 'user_' prefix because OneSignal blocks simple values
 * like '0', '1', '-1', 'null', 'undefined' etc. as external_id.
 *
 * @return array<string, mixed>
 */
public function routeNotificationForOneSignal(): array
{
    return ['include_external_user_ids' => ['user_' . $this->id]];
}
```

> ⚠️ **Important**: The `user_` prefix is required to avoid OneSignal's blocked external_id values. Both Flutter and Laravel must use the same format: `user_{id}`

## 9. Sending Notifications

### From Controller

```php
use App\Notifications\MonitorDownNotification;

public function checkMonitor(Monitor $monitor)
{
    if ($monitor->isDown()) {
        $monitor->user->notify(new MonitorDownNotification($monitor));
    }
}
```

### From Job/Queue

```php
use App\Models\User;
use App\Notifications\MonitorDownNotification;
use Illuminate\Support\Facades\Notification;

// Single user
$user->notify(new MonitorDownNotification($monitor));

// Multiple users
Notification::send($users, new MonitorDownNotification($monitor));
```

## Testing

### Test Database Notification

```php
use App\Models\User;
use App\Models\Monitor;
use App\Notifications\MonitorDownNotification;
use Illuminate\Support\Facades\Notification;

test('sends monitor down notification', function () {
    Notification::fake();

    $user = User::factory()->create();
    $monitor = Monitor::factory()->create(['user_id' => $user->id]);

    $user->notify(new MonitorDownNotification($monitor));

    Notification::assertSentTo($user, MonitorDownNotification::class);
});
```

### Test API Endpoints

```php
use App\Models\User;

test('lists user notifications', function () {
    $user = User::factory()->create();
    $user->notify(new \App\Notifications\MonitorDownNotification($monitor));

    $response = $this->actingAs($user)
        ->getJson('/api/v1/notifications');

    $response->assertOk()
        ->assertJsonStructure([
            'data' => [['id', 'type', 'data', 'read_at', 'created_at']],
            'meta' => ['current_page', 'last_page', 'per_page', 'total'],
        ]);
});
```

## Reference

- [Laravel Notifications Documentation](https://laravel.com/docs/notifications)
- [OneSignal Laravel Channel](https://github.com/laravel-notification-channels/onesignal)
