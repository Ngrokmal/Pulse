import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/di/injection_container.dart' as di;
import '../blocs/group_bloc.dart';

class CreateGroupScreen extends StatefulWidget {
  final String currentUserId;
  const CreateGroupScreen({super.key, required this.currentUserId});

  @override
  State<CreateGroupScreen> createState() => _CreateGroupScreenState();
}

class _CreateGroupScreenState extends State<CreateGroupScreen> {
  late final GroupBloc _groupBloc;
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _memberInputController = TextEditingController();
  final List<String> _memberUids = [];

  @override
  void initState() {
    super.initState();
    _groupBloc = di.sl<GroupBloc>();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _memberInputController.dispose();
    _groupBloc.close();
    super.dispose();
  }

  void _addMember() {
    final uid = _memberInputController.text.trim();
    if (uid.isEmpty) return;
    if (uid == widget.currentUserId) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("You're already in the group")),
      );
      return;
    }
    if (_memberUids.contains(uid)) {
      _memberInputController.clear();
      return;
    }
    setState(() {
      _memberUids.add(uid);
      _memberInputController.clear();
    });
  }

  void _removeMember(String uid) {
    setState(() => _memberUids.remove(uid));
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider<GroupBloc>.value(
      value: _groupBloc,
      child: Scaffold(
        appBar: AppBar(title: const Text('New Group')),
        body: BlocConsumer<GroupBloc, GroupState>(
          listener: (context, state) {
            if (state is GroupErrorState) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(state.message)),
              );
            }
            if (state is GroupCreatedState) {
              Navigator.of(context).pop(state.groupId);
            }
          },
          builder: (context, state) {
            final isCreating = state is GroupCreating;
            return Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: _nameController,
                    enabled: !isCreating,
                    decoration: const InputDecoration(
                      labelText: 'Group name',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _memberInputController,
                          enabled: !isCreating,
                          decoration: const InputDecoration(
                            labelText: 'Add member by user ID',
                            border: OutlineInputBorder(),
                          ),
                          onSubmitted: (_) => _addMember(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.add_circle),
                        onPressed: isCreating ? null : _addMember,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _memberUids
                        .map(
                          (uid) => Chip(
                            label: Text(uid),
                            onDeleted: isCreating ? null : () => _removeMember(uid),
                          ),
                        )
                        .toList(),
                  ),
                  const Spacer(),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: isCreating
                          ? null
                          : () {
                              _groupBloc.add(
                                CreateGroupRequested(
                                  name: _nameController.text,
                                  creatorId: widget.currentUserId,
                                  memberUids: _memberUids,
                                ),
                              );
                            },
                      child: isCreating
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Create Group'),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
