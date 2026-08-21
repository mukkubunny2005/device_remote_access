import '../models/access_session_model.dart';
import 'api_service.dart';

/// Remote access session service wrapping /access/* endpoints.
class AccessService {
  final ApiService _api;

  AccessService({ApiService? api}) : _api = api ?? ApiService();

  Future<AccessSessionModel> requestAccess({
    required String targetDeviceId,
    bool requestControl = true,
  }) async {
    final resp = await _api.post(
      '/access/request',
      data: {
        'target_device_id': targetDeviceId,
        'request_control': requestControl,
      },
    );
    return AccessSessionModel.fromJson(resp.data as Map<String, dynamic>);
  }

  Future<AccessSessionModel> respondAccess({
    required String sessionId,
    required bool accept,
    bool allowControl = true,
  }) async {
    final resp = await _api.post(
      '/access/$sessionId/respond',
      data: {
        'action': accept ? 'accept' : 'reject',
        'allow_control': allowControl,
      },
    );
    return AccessSessionModel.fromJson(resp.data as Map<String, dynamic>);
  }

  Future<AccessSessionModel> endSession(String sessionId) async {
    final resp = await _api.post('/access/$sessionId/end');
    return AccessSessionModel.fromJson(resp.data as Map<String, dynamic>);
  }

  Future<List<AccessSessionModel>> getPendingRequests() async {
    final resp = await _api.get('/access/pending');
    return (resp.data as List)
        .map((e) => AccessSessionModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<AccessSessionModel?> getActiveSession() async {
    final resp = await _api.get('/access/active');
    if (resp.data == null) return null;
    return AccessSessionModel.fromJson(resp.data as Map<String, dynamic>);
  }

  Future<List<AccessSessionModel>> getSessionHistory() async {
    final resp = await _api.get('/access/history');
    return (resp.data as List)
        .map((e) => AccessSessionModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}
