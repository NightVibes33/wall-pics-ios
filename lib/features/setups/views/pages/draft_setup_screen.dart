import 'package:Prism/core/remote_store/remote_collections.dart';
import 'package:Prism/core/remote_store/remote_store_document.dart';
import 'package:Prism/core/remote_store/remote_store_query_specs.dart';
import 'package:Prism/core/remote_store/remote_store_runtime.dart';
import 'package:Prism/core/state/app_state.dart' as app_state;
import 'package:Prism/core/widgets/animated/loader.dart';
import 'package:Prism/features/setups/views/pages/review_screen.dart';
import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';

@RoutePage()
class DraftSetupScreen extends StatefulWidget {
  const DraftSetupScreen();

  @override
  _DraftSetupScreenState createState() => _DraftSetupScreenState();
}

class _DraftSetupScreenState extends State<DraftSetupScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).primaryColor,
      appBar: AppBar(
        title: Text("Setup Drafts", style: TextStyle(color: Theme.of(context).colorScheme.secondary)),
      ),
      body: StreamBuilder<List<RemoteStoreDocument>>(
        stream: remoteStoreClient.watchQuery<RemoteStoreDocument>(
          RemoteStoreQuerySpec(
            collection: RemoteCollections.draftSetups,
            sourceTag: 'draftSetups.list',
            filters: <RemoteStoreFilter>[
              RemoteStoreFilter(field: "email", op: RemoteStoreFilterOp.isEqualTo, value: app_state.prismUser.email),
              const RemoteStoreFilter(field: "review", op: RemoteStoreFilterOp.isEqualTo, value: false),
            ],
            orderBy: const <RemoteStoreOrderBy>[RemoteStoreOrderBy(field: 'created_at', descending: true)],
            isStream: true,
          ),
          (data, docId) => RemoteStoreDocument(docId, data),
        ),
        builder: (BuildContext context, AsyncSnapshot<List<RemoteStoreDocument>> snapshot) {
          if (!snapshot.hasData) {
            return Center(child: Loader());
          } else {
            if (snapshot.data!.isNotEmpty) {
              return ListView.builder(
                itemCount: snapshot.data!.length,
                itemBuilder: (context, index) => SetupTile(snapshot.data![index], true),
              );
            } else {
              return const Padding(
                padding: EdgeInsets.all(16.0),
                child: Center(
                  child: Text(
                    "Your saved setup drafts show up here. Simply click the Save button when uploading a setup to save the draft.",
                  ),
                ),
              );
            }
          }
        },
      ),
    );
  }
}
