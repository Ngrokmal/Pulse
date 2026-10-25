import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/di/injection_container.dart' as di;
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/common_loading_widget.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/error_state_view.dart';
import '../../../profile/domain/entities/profile_entity.dart';
import '../../../profile/domain/entities/profile_visibility.dart';
import '../../../profile/domain/usecases/get_relationship_status_usecase.dart';
import '../../../profile/presentation/pages/friend_profile_screen.dart';
import '../../../profile/presentation/pages/my_profile_screen.dart';
import '../../../profile/presentation/pages/non_friend_profile_screen.dart';
import '../blocs/user_search_bloc.dart';
import '../widgets/search_result_tile.dart';
import '../widgets/user_search_bar.dart';

class SearchScreen extends StatefulWidget {
  final String currentUserId;
  const SearchScreen({super.key, required this.currentUserId});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  late final UserSearchBloc _searchBloc;
  final TextEditingController _controller = TextEditingController();

  @override
  void initState() {
    super.initState();
    _searchBloc = di.sl<UserSearchBloc>();
  }

  @override
  void dispose() {
    _controller.dispose();
    _searchBloc.close();
    super.dispose();
  }

  void _onChanged(String query) {
    _searchBloc.add(SearchQueryChanged(query: query, viewerUid: widget.currentUserId));
  }

  void _onClear() {
    _searchBloc.add(ClearSearchRequested());
  }

  Future<void> _openProfile(ProfileEntity profile) async {
    final relationshipResult = await di.sl<GetRelationshipStatusUseCase>()(
      viewerUid: widget.currentUserId,
      profileUid: profile.uid,
    );

    if (!mounted) return;

    final visibility = relationshipResult.fold((_) => ProfileVisibility.nonFriend, (v) => v);

    Widget destination;
    switch (visibility) {
      case ProfileVisibility.owner:
        destination = MyProfileScreen(uid: profile.uid);
        break;
      case ProfileVisibility.friend:
        destination = FriendProfileScreen(uid: profile.uid, viewerUid: widget.currentUserId);
        break;
      case ProfileVisibility.nonFriend:
      case ProfileVisibility.blocked:
        destination = NonFriendProfileScreen(uid: profile.uid, viewerUid: widget.currentUserId);
        break;
    }

    Navigator.of(context).push(MaterialPageRoute(builder: (_) => destination));
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider<UserSearchBloc>.value(
      value: _searchBloc,
      child: Scaffold(
        backgroundColor: AppColors.backgroundBottom,
        appBar: AppBar(title: const Text('Search')),
        body: Column(
          children: [
            UserSearchBar(controller: _controller, onChanged: _onChanged, onClear: _onClear),
            Expanded(
              child: BlocBuilder<UserSearchBloc, UserSearchState>(
                builder: (context, state) => _buildBody(context, state),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context, UserSearchState state) {
    if (state is UserSearchInitial) {
      return const EmptyState(
        key: ValueKey('search-initial'),
        icon: Icons.search,
        title: 'Search for people',
        subtitle: 'Find users by username or display name',
      );
    }
    if (state is UserSearchLoading) {
      return const CommonLoadingWidget(key: ValueKey('search-loading'), message: 'Searching…');
    }
    if (state is UserSearchErrorState) {
      return ErrorStateView(key: const ValueKey('search-error'), message: state.message);
    }
    if (state is UserSearchLoadedState) {
      if (state.results.isEmpty) {
        return EmptyState(
          key: const ValueKey('search-empty'),
          icon: Icons.search_off,
          title: 'No users match "${state.query}"',
          subtitle: 'Try a different username or name',
        );
      }
      return ListView.separated(
        key: const ValueKey('search-loaded'),
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.small),
        itemCount: state.results.length,
        separatorBuilder: (_, __) => const SizedBox(height: 2),
        itemBuilder: (context, index) {
          final profile = state.results[index];
          return SearchResultTile(
            key: ValueKey(profile.uid),
            profile: profile,
            onTap: () => _openProfile(profile),
          );
        },
      );
    }
    return const SizedBox.shrink(key: ValueKey('search-blank'));
  }
}
