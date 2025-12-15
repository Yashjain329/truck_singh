<p align="center">
  <a href="https://flutter.dev/"><img src="https://img.shields.io/badge/Flutter-3.x-blue?logo=flutter"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-MIT-yellow.svg"></a>
  <a href="https://github.com/Yashjain329/truck_singh/stargazers"><img src="https://img.shields.io/github/stars/Yashjain329/truck_singh?style=social"></a>
  <img src="https://img.shields.io/github/forks/Yashjain329/truck_singh?style=social">
  <img src="https://img.shields.io/github/last-commit/Yashjain329/truck_singh">
</p>

# 🚚 Truck Singh

`Truck Singh` is a **cross-platform Flutter app** (Android, iOS, Web) that lets users **manage logistics and transportation**, using **Supabase** for authentication + storage and a **custom backend API** for deep analysis and insights.

---

## 🚀 Features

* 🔑 **Authentication** with Supabase (email/password and social login)
* ☁️ **Uploads** to Supabase Storage (`shipment-documents` bucket)
* 🗄️ **Metadata tracking** in a secure `shipments` table (with RLS)
* 🧠 **AI-powered Chatbot** for answering user queries.
* 🚚 **Shipment and Driver Tracking** in real-time.
*  dashboards for **Admin, and User**.
* 📦 **Shipment Management** with live tracking of shipments and drivers.
* 📄 **Document Management** for drivers and trucks.
* 📝 **Complaints and Ratings** system for shipments.
* 🔔 **Real-time Notifications** for important events.
* 📊 **Logistics analysis endpoints**
    * `/analyze_shipment`
    * `/recommend_route`
    * `/track_shipment`
    * `/download_report`
* 🎨 **Modern UI** with a custom theme (`theme.dart`)
* ⚡ **Optimized performance**
    * Cached data for offline access
    * Smooth file uploads with async streaming
* 📱 Multiple screens: Login, Dashboard, Shipment Details, Track Shipment, and more.

---

## ⚙️ Prerequisites

* [Flutter SDK](https://docs.flutter.dev/get-started/install) ≥ **3.8**
* Active [Supabase project](https://app.supabase.com)
* Configured backend (already prefilled in `.env`)

---

## 🛠️ Setup

### 1. Clone repository

```bash
git clone https://github.com/your-org/truck_singh.git
cd truck_singh
```

### 2. Configure environment

Copy the example file and set values:

```bash
cp .env.example .env
```

Fill in your environment variables:

```env
SUPABASE_URL=your-supabase-url
SUPABASE_ANON_KEY=your-supabase-anon-key
GOOGLE_MAPS_API_KEY=your-google-maps-api-key
ONESIGNAL_API_KEY=your-onesignal-api-key
ONESIGNAL_APP_ID=your-onesignal-app-id
GEMINI_PROXY_URL=your-gemini-proxy-url
GEMINI_API_KEY=your-gemini-api-key
```

---

### 3. Supabase setup (storage + database)

#### a) Create Storage Buckets

1. Open [Supabase Dashboard → Storage](https://app.supabase.com)
2. Click **New bucket** and create the following buckets:
    * `shipment-documents` (Private)
    * `chat_attachments` (Private)

#### b) Create Tables

Paste the following SQL queries in your Supabase SQL editor to create the necessary tables:

<details>
<summary>Click to view table definitions</summary>

##### `user_profiles`

```sql
CREATE TABLE public.user_profiles (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  user_id uuid NOT NULL,
  custom_user_id text NOT NULL,
  "role" text NOT NULL,
  name text NOT NULL,
  date_of_birth text NOT NULL,
  mobile_number text NOT NULL,
  email text NULL,
  profile_completed boolean NOT NULL DEFAULT false,
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT user_profiles_pkey PRIMARY KEY (id),
  CONSTRAINT user_profiles_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id)
);
```

##### `shipment`

```sql
CREATE TABLE public.shipment (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  shipment_id text NOT NULL,
  booking_status text NOT NULL DEFAULT 'Pending'::text,
  assigned_agent text NULL,
  assigned_driver text NULL,
  assigned_truck text NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT shipment_pkey PRIMARY KEY (id)
);
```

##### `trucks`

```sql
CREATE TABLE public.trucks (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  truck_number text NOT NULL,
  truck_admin text NOT NULL,
  status text NOT NULL DEFAULT 'available'::text,
  current_location jsonb NULL,
  CONSTRAINT trucks_pkey PRIMARY KEY (id)
);
```

##### `driver_relation`

```sql
CREATE TABLE public.driver_relation (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  driver_custom_id text NOT NULL,
  owner_custom_id text NOT NULL,
  CONSTRAINT driver_relation_pkey PRIMARY KEY (id)
);
```

##### `chat_messages`

```sql
CREATE TABLE public.chat_messages (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  room_id text NOT NULL,
  sender_id text NOT NULL,
  content text NOT NULL,
  message_type text NOT NULL DEFAULT 'text'::text,
  attachment_url text NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT chat_messages_pkey PRIMARY KEY (id)
);
```

##### `complaints`

```sql
CREATE TABLE public.complaints (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  user_id uuid NOT NULL,
  target_user_id text NULL,
  complaint_type text NOT NULL,
  subject text NOT NULL,
  complaint text NOT NULL,
  status text NOT NULL DEFAULT 'Open'::text,
  managed_by text NULL,
  agent_justification text NULL,
  is_clarified boolean NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT complaints_pkey PRIMARY KEY (id),
  CONSTRAINT complaints_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id)
);
```

</details>

#### c) Enable Row Level Security (RLS)

It is highly recommended to enable Row Level Security (RLS) on your tables to control access to your data. You can create policies to restrict access to data based on user roles and permissions. You can find examples of RLS policies in the Supabase documentation.

---

### 4. Redirect URI (Deep Linking)

#### Android

Add inside `<activity>` in `android/app/src/main/AndroidManifest.xml`:

```xml
<intent-filter>
  <action android:name="android.intent.action.VIEW" />
  <category android:name="android.intent.category.DEFAULT" />
  <category android:name="android.intent.category.BROWSABLE" />
  <data android:scheme="com.trucksingh.app" android:host="login-callback" />
</intent-filter>
```

#### iOS

Add in `ios/Runner/Info.plist`:

```xml
<key>CFBundleURLTypes</key>
<array>
  <dict>
    <key>CFBundleURLSchemes</key>
    <array>
      <string>com.trucksingh.app</string>
    </array>
  </dict>
</array>
```

> Also declare camera & photo library permissions in Info.plist.

---

## ▶️ Running the app

```bash
flutter pub get
flutter run
```

To build web:

```bash
flutter build web --release
```

Deploy `build/web` to Netlify, Vercel, or GitHub Pages.

---

## 🧩 Project structure

```
lib/
 ├── main.dart                 # Entry point
 ├── config/                   # Configuration files
 │   ├── theme.dart              # App theme
 ├── features/                 # Feature-based modules
 │   ├── admin/
 │   ├── auth/
 │   ├── bilty/
 │   ├── chat/
 │   ├── complains/
 │   ├── driver_documents/
 │   ├── driver_status/
 │   ├── invoice/
 │   ├── laod_assignment/
 │   ├── mydrivers/
 │   ├── mydriversdocs/
 │   ├── mytruck/
 │   ├── mytruck_docs/
 │   ├── notifications/
 │   ├── ratings/
 │   ├── Report Analysis/
 │   ├── settings/
 │   ├── shipment/
 │   ├── sos/
 │   ├── tracking/
 │   └── trips/
 ├── providers/                # State management providers
 │   └── chat_provider.dart
 ├── services/                 # Business logic services
 │   ├── gemini_service.dart
 │   └── intent_parser.dart
 ├── widgets/                  # Reusable widgets
 │   └── chat_screen.dart
 └── dashboard/                # Dashboard related files
```

---

## 🔗 API Endpoints

The backend (`BACKEND_URL`) exposes:

* `POST /analyze_shipment`
* `POST /recommend_route`
* `POST /track_shipment`
* `POST /download_report`

### ✅ Automated Flow

```
User creates shipment
   ↓
UploadService → Supabase Storage
   ↓
Insert metadata → shipment
   ↓
Generate signed URL → send to backend API
   ↓
Backend runs analysis → returns JSON
   ↓
ApiService saves results → Supabase table
   ↓
Display insights in Shipment Details screen
```

---

## 📜 License

This project is licensed under the **MIT License**.
See the [LICENSE](LICENSE) file for full details.

---

