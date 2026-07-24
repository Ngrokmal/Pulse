import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/errors/error_mapper.dart';
import '../../../profile/domain/entities/profile_entity.dart';
import '../../domain/usecases/search_users_usecase.dart';

const _kDebounceDuration = Duration(milliseconds: 400);
const _kSearchTimeout = Duration(seconds: 15);

abstract class UserSearchEvent {}

class SearchQueryChanged extends UserSearchEvent {
  final String query;
  final String viewerUid;
  SearchQueryChanged({required this.query, required this.viewerUid});
}

class ClearSearchRequested extends UserSearchEvent {}

class _SearchDebounceElapsed extends UserSearchEvent {
  final String query;
  final String viewerUid;
  _SearchDebounceElapsed({required this.query, required this.viewerUid});
}

abstract class UserSearchState {}

class UserSearchInitial extends UserSearchState {}

class UserSearchLoading extends UserSearchState {}

class UserSearchLoadedState extends UserSearchState {
  final List<ProfileEntity> results;
  final String query;
  UserSearchLoadedState({required this.results, required this.query});
}

class UserSearchErrorState extends UserSearchState {
  final String message;
  UserSearchErrorState({required this.message});
}

class UserSearchBloc extends Bloc<UserSearchEvent, UserSearchState> {
  final SearchUsersUseCase searchUsersUseCase;

  Timer? _debounceTimer;
  int _requestToken = 0;
  String? _lastDispatchedQuery;

  UserSearchBloc({required this.searchUsersUseCase}) : super(UserSearchInitial()) {
    on<SearchQueryChanged>(_onQueryChanged);
    on<_SearchDebounceElapsed>(_onDebounceElapsed);
    on<ClearSearchRequested>(_onClearSearch);
  }

  void _onQueryChanged(SearchQueryChanged event, Emitter<UserSearchState> emit) {
    _debounceTimer?.cancel();
    final trimmed = event.query.trim();
    if (trimmed.isEmpty) {
      _requestToken++;
      _lastDispatchedQuery = null;
      emit(UserSearchInitial());
      return;
    }
    emit(UserSearchLoading());
    _debounceTimer = Timer(_kDebounceDuration, () {
      if (!isClosed) add(_SearchDebounceElapsed(query: trimmed, viewerUid: event.viewerUid));
    });
  }

  Future<void> _onDebounceElapsed(_SearchDebounceElapsed event, Emitter<UserSearchState> emit) async {
    if (event.query == _lastDispatchedQuery) return;
    _lastDispatchedQuery = event.query;
    final myToken = ++_requestToken;
    try {
      final result = await searchUsersUseCase(query: event.query, viewerUid: event.viewerUid).timeout(_kSearchTimeout);
      if (myToken != _requestToken || emit.isDone) return;
      result.fold(
        (failure) => emit(UserSearchErrorState(message: friendlyErrorMessage(failure))),
        (results) => emit(UserSearchLoadedState(results: results, query: event.query)),
      );
    } catch (error) {
      if (myToken != _requestToken || emit.isDone) return;
      emit(UserSearchErrorState(message: friendlyErrorMessage(error)));
    }
  }

  void _onClearSearch(ClearSearchRequested event, Emitter<UserSearchState> emit) {
    _debounceTimer?.cancel();
    _requestToken++;
    _lastDispatchedQuery = null;
    emit(UserSearchInitial());
  }

  @override
  Future<void> close() {
    _debounceTimer?.cancel();
    return super.close();
  }
}
