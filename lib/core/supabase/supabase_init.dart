import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseInit {
  SupabaseInit._();

  static const String _url = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://eqqlscbklniuttvrglmo.supabase.co',
  );
  static const String _anonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImVxcWxzY2JrbG5pdXR0dnJnbG1vIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODUwNjM2NDgsImV4cCI6MjEwMDYzOTY0OH0.GZiWJbwRT0j0fP9AsB6f2sf_lmOEqf9bitxJOfY-jZs',
  );

  static Future<void> init() async {
    await Supabase.initialize(url: _url, anonKey: _anonKey);
  }

  static SupabaseClient get client => Supabase.instance.client;
}
