# Laravel Backend Setup

## Table of Contents

- <a name="toc-overview"></a>[Overview](#overview)
- <a name="toc-prerequisites"></a>[Prerequisites](#prerequisites)
- <a name="toc-database-setup"></a>[Database Setup](#database-setup)
- <a name="toc-models"></a>[Models](#models)
- <a name="toc-notification-class"></a>[Notification Class](#notification-class)
- <a name="toc-api-controllers"></a>[API Controllers](#api-controllers)
- <a name="toc-api-routes"></a>[API Routes](#api-routes)
- <a name="toc-onesignal-push"></a>[OneSignal Push Integration](#onesignal-push)
- <a name="toc-sending"></a>[Sending Notifications](#sending)
- <a name="toc-api-contract"></a>[API Contract Reference](#api-contract)
- <a name="toc-testing"></a>[Testing](#testing)

---

## <a name="overview"></a>Overview

Magic Notifications works with any backend that provides REST API endpoints. This guide shows how to implement the notification backend using **Laravel's built-in notification system** — the recommended approach for Laravel-based projects.

> [!NOTE]
> This guide covers the Laravel backend side. For Flutter client setup, see [Installation](../getting-started/installation.md) and [Configuration](../getting-started/configuration.md).

---

## <a name="prerequisites"></a>Prerequisites

- Laravel 10.x or higher
- PHP 8.1+
- Composer

---

## <a name="database-setup"></a>Database Setup

### Notifications Table

Laravel provides a built-in artisan command:

```bash
php artisan make:notifications-table
php artisan migrate
```

This creates the standard `notifications` table:

| Column | Type | Description |
|--------|------|-------------|
| id | uuid | Primary key |
| type | string | Notification class name |
| notifiable_type | string | Model type (e.g., `App\Models\User`) |
| notifiable_id | bigint | Model ID |
| data | json | Notification payload |
| read_at | timestamp | When marked as read (`null` = unread) |
| created_at | timestamp | Creation time |
| updated_at | timestamp | Last update time |

### Notification Preferences Table

```bash
php artisan make:migration create_notification_preferences_table
```

```php
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

```bash
php artisan migrate
```

---

## <a name="models"></a>Models

### User Model

Ensure your User model uses the `Notifiable` trait:

```php
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

### NotificationPreference Model

```bash
php artisan make:model NotificationPreference
```

```php
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

---

## <a name="notification-class"></a>Notification Class

```bash
php artisan make:notification MonitorDownNotification
```

```php
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

    public function toArray(object $notifiable): array
    {
        return [
            'title' => 'Monitor Down',
            'body' => "Your monitor '{$this->monitor->name}' is not responding.",
            'action_url' => "/monitors/{$this->monitor->id}",
            'monitor_id' => $this->monitor->id,
        ];
    }

    public function databaseType(object $notifiable): string
    {
        return 'monitor_down';
    }

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

---

## <a name="api-controllers"></a>API Controllers

### NotificationController

```bash
php artisan make:controller Api/V1/NotificationController
```

```php
namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use Illuminate\Http\Request;
use Illuminate\Http\JsonResponse;

class NotificationController extends Controller
{
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

    public function unreadCount(Request $request): JsonResponse
    {
        $count = $request->user()->unreadNotifications()->count();

        return response()->json(['count' => $count]);
    }

    public function markAsRead(Request $request, string $id): JsonResponse
    {
        $notification = $request->user()
            ->notifications()
            ->findOrFail($id);

        $notification->markAsRead();

        return response()->json(['message' => 'Notification marked as read']);
    }

    public function markAllAsRead(Request $request): JsonResponse
    {
        $request->user()->unreadNotifications->markAsRead();

        return response()->json(['message' => 'All notifications marked as read']);
    }

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
namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Models\NotificationPreference;
use Illuminate\Http\Request;
use Illuminate\Http\JsonResponse;

class NotificationPreferenceController extends Controller
{
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

        $prefs->fill($validated);
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

---

## <a name="api-routes"></a>API Routes

In `routes/api/v1.php`:

```php
use App\Http\Controllers\Api\V1\NotificationController;
use App\Http\Controllers\Api\V1\NotificationPreferenceController;
use Illuminate\Support\Facades\Route;

Route::middleware('auth:sanctum')->group(function () {
    Route::get('notifications', [NotificationController::class, 'index']);
    Route::get('notifications/unread-count', [NotificationController::class, 'unreadCount']);
    Route::post('notifications/{id}/read', [NotificationController::class, 'markAsRead']);
    Route::post('notifications/read-all', [NotificationController::class, 'markAllAsRead']);
    Route::delete('notifications/{id}', [NotificationController::class, 'destroy']);

    Route::get('notification-preferences', [NotificationPreferenceController::class, 'show']);
    Route::put('notification-preferences', [NotificationPreferenceController::class, 'update']);
});
```

---

## <a name="onesignal-push"></a>OneSignal Push Integration

For push notifications via OneSignal, install the Laravel notification channel:

```bash
composer require laravel-notification-channels/onesignal
composer require berkayk/onesignal-laravel
```

```bash
php artisan vendor:publish --provider="Berkayk\OneSignal\OneSignalServiceProvider"
```

Add to `.env`:

```env
ONESIGNAL_APP_ID=your-onesignal-app-id
ONESIGNAL_REST_API_KEY=your-onesignal-rest-api-key
```

> [!NOTE]
> Get the REST API Key from OneSignal Dashboard → Settings → Keys & IDs. Use the "REST API Key" (starts with `os_v2_app_...`), not the "User Auth Key".

### Update Notification Class

Add the OneSignal channel to your notification:

```php
use NotificationChannels\OneSignal\OneSignalChannel;
use NotificationChannels\OneSignal\OneSignalMessage;

public function via(object $notifiable): array
{
    $channels = ['database'];
    $prefs = $notifiable->notificationPreference;

    if (!$prefs || $prefs->push_enabled) {
        $channels[] = OneSignalChannel::class;
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
```

### Route User to OneSignal

Add to your User model:

```php
/**
 * Route notifications for OneSignal channel.
 *
 * IMPORTANT: The external_user_id must match what the Flutter app sets
 * when calling Notify.initializePush('user_' + user.id).
 */
public function routeNotificationForOneSignal(): array
{
    return ['include_external_user_ids' => ['user_' . $this->id]];
}
```

> [!TIP]
> The `user_` prefix is required to avoid OneSignal's blocked external_id values. Both Flutter and Laravel must use the same format: `user_{id}`.

---

## <a name="sending"></a>Sending Notifications

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
use Illuminate\Support\Facades\Notification;

// Single user
$user->notify(new MonitorDownNotification($monitor));

// Multiple users
Notification::send($users, new MonitorDownNotification($monitor));
```

---

## <a name="api-contract"></a>API Contract Reference

These are the endpoints the Flutter plugin expects from your backend:

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/notifications` | GET | List user notifications (paginated) |
| `/notifications/unread-count` | GET | Get unread notification count |
| `/notifications/{id}/read` | POST | Mark single notification as read |
| `/notifications/read-all` | POST | Mark all notifications as read |
| `/notifications/{id}` | DELETE | Delete a notification |
| `/notification-preferences` | GET | Get user notification preferences |
| `/notification-preferences` | PUT | Update user preferences |

### Response Formats

**GET /notifications**:

```json
{
  "data": [
    {
      "id": "550e8400-e29b-41d4-a716-446655440000",
      "type": "monitor_down",
      "data": {
        "title": "Monitor Alert",
        "body": "Your monitor 'API Server' is down",
        "action_url": "/monitors/1"
      },
      "read_at": null,
      "created_at": "2024-01-15T10:30:00Z"
    }
  ],
  "meta": {
    "current_page": 1,
    "last_page": 3,
    "per_page": 15,
    "total": 42
  }
}
```

**GET /notifications/unread-count**:

```json
{
  "count": 5
}
```

**GET /notification-preferences**:

```json
{
  "data": {
    "push_enabled": true,
    "email_enabled": false,
    "in_app_enabled": true,
    "type_preferences": {
      "monitor_down": { "push": true, "email": true, "in_app": true },
      "monitor_up": { "push": false, "email": false, "in_app": true }
    }
  }
}
```

---

## <a name="testing"></a>Testing

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

---

**Related**

- [Laravel Notifications Documentation](https://laravel.com/docs/notifications)
- [OneSignal Laravel Channel](https://github.com/laravel-notification-channels/onesignal)
- [Installation](https://magic.fluttersdk.com/packages/notifications/getting-started/installation)
- [Channels](https://magic.fluttersdk.com/packages/notifications/basics/channels)
