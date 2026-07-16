import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseConfig {
  static const String url = 'https://eamnrhcnqzpbxitrwcss.supabase.co';
  static const String anonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImVhbW5yaGNucXpwYnhpdHJ3Y3NzIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODQwMjkyODQsImV4cCI6MjA5OTYwNTI4NH0.HZ-fcs9UIua1YzfK2DluH00O0XwOBDzfa0kxcLM9KV4';

  static Future<void> init() async {
    await Supabase.initialize(
      url: url,
      anonKey: anonKey,
    );
  }
}

final supabase = Supabase.instance.client;
