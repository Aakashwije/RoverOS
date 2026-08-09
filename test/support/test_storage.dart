import 'package:roveros/services/storage_service.dart';

/// Builds a [StorageService] backed by in-memory preferences.
///
/// Call `SharedPreferences.setMockInitialValues` first to seed stored state.
Future<StorageService> createTestStorage() async => StorageService.create();
