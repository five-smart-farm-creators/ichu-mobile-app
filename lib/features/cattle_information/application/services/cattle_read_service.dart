import 'package:flutter/foundation.dart';

import '../../../iam/application/facades/authorized_ranch_session.dart';
import '../../domain/model/cattle.dart';
import '../../domain/model/cattle_failure.dart';
import '../../domain/model/cattle_search.dart';
import '../../domain/repositories/cattle_repository.dart';

enum CattleLoadStatus { idle, loading, ready, unavailable }

/// Coordinates ranch-scoped cattle reads without retaining authorization data.
final class CattleReadService extends ChangeNotifier {
  CattleReadService({
    required AuthorizedRanchSession access,
    required this._cattle,
  }) : _access = access,
       _observedContext = access.context {
    _access.addListener(_onAccessChanged);
  }

  final AuthorizedRanchSession _access;
  final CattleRepository _cattle;
  AuthorizedRanchContext? _observedContext;
  AuthorizedRanchContext? _listContext;
  AuthorizedRanchContext? _profileContext;
  CattleLoadStatus _status = CattleLoadStatus.idle;
  CattleLoadStatus _profileStatus = CattleLoadStatus.idle;
  List<Cattle> _animals = const <Cattle>[];
  CattleSearch _query = const CattleSearch();
  CattleFailure? _error;
  CattleProfile? _profile;
  CattleFailure? _profileError;
  int _listGeneration = 0;
  int _profileGeneration = 0;
  int _revision = 0;
  bool _disposed = false;
  AuthorizedRanchContext? _pendingListContext;
  CattleSearch? _pendingListQuery;
  Future<bool>? _pendingList;
  AuthorizedRanchContext? _pendingProfileContext;
  String? _pendingProfileId;
  Future<bool>? _pendingProfile;

  CattleLoadStatus get status =>
      _scopeMatches(_listContext) ? _status : CattleLoadStatus.idle;
  CattleLoadStatus get profileStatus =>
      _scopeMatches(_profileContext) ? _profileStatus : CattleLoadStatus.idle;
  bool get hasContext => !_disposed && _access.context != null;
  bool get canLoad =>
      hasContext && _cattle.isConfigured && status != CattleLoadStatus.loading;
  String? get ranchName => hasContext ? _access.context!.ranchName : null;
  List<Cattle> get animals =>
      _scopeMatches(_listContext) ? _animals : const <Cattle>[];
  CattleSearch get query =>
      _scopeMatches(_listContext) ? _query : const CattleSearch();
  CattleFailure? get error => _scopeMatches(_listContext) ? _error : null;
  CattleProfile? get profile =>
      _scopeMatches(_profileContext) ? _profile : null;
  CattleFailure? get profileError =>
      _scopeMatches(_profileContext) ? _profileError : null;
  bool get canGoNext =>
      status == CattleLoadStatus.ready && animals.length == query.pageSize;
  bool get canGoPrevious =>
      hasContext && status != CattleLoadStatus.loading && query.page > 1;
  int get revision => _revision;

  Future<bool> load({CattleSearch? query}) {
    final context = _currentContext;
    if (context == null) return Future<bool>.value(false);
    final rawQuery =
        query ?? (_scopeMatches(_listContext) ? _query : const CattleSearch());
    final requested = CattleSearch(
      earTag: rawQuery.earTag.trim(),
      status: rawQuery.status,
      page: rawQuery.page,
      pageSize: rawQuery.pageSize,
    );
    if (!requested.isValid) {
      _listGeneration++;
      _pendingList = null;
      _pendingListContext = null;
      _pendingListQuery = null;
      _listContext = context;
      _query = requested;
      _animals = const <Cattle>[];
      _error = const CattleFailure(CattleFailureCode.invalidSearch);
      _status = CattleLoadStatus.unavailable;
      _notify();
      return Future<bool>.value(false);
    }
    if (identical(_pendingListContext, context) &&
        _pendingListQuery == requested &&
        _pendingList != null) {
      return _pendingList!;
    }
    final generation = ++_listGeneration;
    _listContext = context;
    _query = requested;
    _animals = const <Cattle>[];
    _error = null;
    _status = CattleLoadStatus.loading;
    _pendingList = null;
    _pendingListContext = null;
    _pendingListQuery = null;
    _notify();
    if (!_cattle.isConfigured) {
      _error = const CattleFailure(CattleFailureCode.configuration);
      _status = CattleLoadStatus.unavailable;
      _notify();
      return Future<bool>.value(false);
    }
    _pendingListContext = context;
    _pendingListQuery = requested;
    final future = _performList(context, requested, generation);
    _pendingList = future;
    return future;
  }

  Future<bool> nextPage() => canGoNext
      ? load(query: query.atPage(query.page + 1))
      : Future<bool>.value(false);
  Future<bool> previousPage() => canGoPrevious
      ? load(query: query.atPage(query.page - 1))
      : Future<bool>.value(false);

  Future<bool> loadProfile(String cattleId) {
    final context = _currentContext;
    if (context == null || cattleId.trim().isEmpty) {
      _clearProfile();
      _profileContext = context;
      _profileError = const CattleFailure(CattleFailureCode.notFound);
      _profileStatus = CattleLoadStatus.unavailable;
      _notify();
      return Future<bool>.value(false);
    }
    if (identical(_pendingProfileContext, context) &&
        _pendingProfileId == cattleId &&
        _pendingProfile != null) {
      return _pendingProfile!;
    }
    final generation = ++_profileGeneration;
    _profileContext = context;
    _profile = null;
    _profileError = null;
    _profileStatus = CattleLoadStatus.loading;
    _pendingProfile = null;
    _pendingProfileContext = null;
    _pendingProfileId = null;
    _notify();
    if (!_cattle.isConfigured) {
      _profileError = const CattleFailure(CattleFailureCode.configuration);
      _profileStatus = CattleLoadStatus.unavailable;
      _notify();
      return Future<bool>.value(false);
    }
    _pendingProfileContext = context;
    _pendingProfileId = cattleId;
    final future = _performProfile(context, cattleId, generation);
    _pendingProfile = future;
    return future;
  }

  void clearProfile() {
    _profileGeneration++;
    _pendingProfile = null;
    _pendingProfileContext = null;
    _pendingProfileId = null;
    _profileContext = _currentContext;
    _profile = null;
    _profileError = null;
    _profileStatus = CattleLoadStatus.idle;
    _notify();
  }

  Future<bool> _performList(
    AuthorizedRanchContext context,
    CattleSearch requested,
    int generation,
  ) async {
    try {
      final response = await _cattle.search(context.ranchId, requested);
      if (!_validListResponse(response, requested, context)) {
        throw const CattleFailure(CattleFailureCode.invalidResponse);
      }
      if (!_isCurrentList(context, generation)) return false;
      _animals = List<Cattle>.unmodifiable(response);
      _error = null;
      _status = CattleLoadStatus.ready;
      _notify();
      return true;
    } catch (error) {
      if (!_isCurrentList(context, generation)) return false;
      final failure = _asFailure(error);
      if (_isPermissionFailure(failure)) {
        _invalidateBoth(failure);
      } else {
        _animals = const <Cattle>[];
        _error = failure;
        _status = CattleLoadStatus.unavailable;
        _notify();
      }
      return false;
    } finally {
      if (identical(_pendingListContext, context) &&
          _pendingListQuery == requested &&
          _listGeneration == generation) {
        _pendingList = null;
        _pendingListContext = null;
        _pendingListQuery = null;
      }
    }
  }

  Future<bool> _performProfile(
    AuthorizedRanchContext context,
    String cattleId,
    int generation,
  ) async {
    try {
      final response = await _cattle.profile(context.ranchId, cattleId);
      if (response.cattle.id.toLowerCase() != cattleId.toLowerCase() ||
          response.cattle.ranchId.toLowerCase() !=
              context.ranchId.toLowerCase()) {
        throw const CattleFailure(CattleFailureCode.invalidResponse);
      }
      if (!_isCurrentProfile(context, generation)) return false;
      _profile = response;
      _profileError = null;
      _profileStatus = CattleLoadStatus.ready;
      _notify();
      return true;
    } catch (error) {
      if (!_isCurrentProfile(context, generation)) return false;
      final failure = _asFailure(error);
      if (_isPermissionFailure(failure)) {
        _invalidateBoth(failure);
      } else {
        _profile = null;
        _profileError = failure;
        _profileStatus = CattleLoadStatus.unavailable;
        _notify();
      }
      return false;
    } finally {
      if (identical(_pendingProfileContext, context) &&
          _pendingProfileId == cattleId &&
          _profileGeneration == generation) {
        _pendingProfile = null;
        _pendingProfileContext = null;
        _pendingProfileId = null;
      }
    }
  }

  bool _validListResponse(
    List<Cattle> response,
    CattleSearch requested,
    AuthorizedRanchContext context,
  ) {
    if (response.length > requested.pageSize) return false;
    final ids = <String>{};
    for (final cattle in response) {
      if (cattle.ranchId.toLowerCase() != context.ranchId.toLowerCase() ||
          cattle.id.trim().isEmpty ||
          !ids.add(cattle.id.toLowerCase())) {
        return false;
      }
    }
    return true;
  }

  bool _isCurrentList(AuthorizedRanchContext context, int generation) =>
      !_disposed &&
      _listGeneration == generation &&
      identical(_listContext, context) &&
      _access.isCurrent(context);
  bool _isCurrentProfile(AuthorizedRanchContext context, int generation) =>
      !_disposed &&
      _profileGeneration == generation &&
      identical(_profileContext, context) &&
      _access.isCurrent(context);
  bool _scopeMatches(AuthorizedRanchContext? stored) =>
      !_disposed && stored != null && identical(_currentContext, stored);
  AuthorizedRanchContext? get _currentContext =>
      _disposed ? null : _access.context;

  void _onAccessChanged() {
    if (_disposed) return;
    final next = _access.context;
    if (identical(next, _observedContext)) return;
    _observedContext = next;
    _listGeneration++;
    _profileGeneration++;
    _listContext = next;
    _profileContext = next;
    _animals = const <Cattle>[];
    _profile = null;
    _query = const CattleSearch();
    _error = null;
    _profileError = null;
    _status = CattleLoadStatus.idle;
    _profileStatus = CattleLoadStatus.idle;
    _revision++;
    _pendingList = null;
    _pendingProfile = null;
    _pendingListContext = null;
    _pendingProfileContext = null;
    _pendingListQuery = null;
    _pendingProfileId = null;
    _notify();
  }

  void _invalidateBoth(CattleFailure failure) {
    _listGeneration++;
    _profileGeneration++;
    _listContext = _currentContext;
    _profileContext = _currentContext;
    _animals = const <Cattle>[];
    _profile = null;
    _query = const CattleSearch();
    _error = failure;
    _profileError = failure;
    _status = CattleLoadStatus.unavailable;
    _profileStatus = CattleLoadStatus.unavailable;
    _pendingList = null;
    _pendingProfile = null;
    _pendingListContext = null;
    _pendingProfileContext = null;
    _pendingListQuery = null;
    _pendingProfileId = null;
    _notify();
  }

  void _clearProfile() {
    _profileGeneration++;
    _pendingProfile = null;
    _pendingProfileContext = null;
    _pendingProfileId = null;
    _profile = null;
    _profileError = null;
    _profileStatus = CattleLoadStatus.idle;
  }

  CattleFailure _asFailure(Object error) => error is CattleFailure
      ? error
      : const CattleFailure(CattleFailureCode.unknown);
  bool _isPermissionFailure(CattleFailure failure) =>
      failure.code == CattleFailureCode.unauthenticated ||
      failure.code == CattleFailureCode.forbidden ||
      failure.code == CattleFailureCode.contextUnavailable;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _listGeneration++;
    _profileGeneration++;
    _access.removeListener(_onAccessChanged);
    super.dispose();
  }
}
