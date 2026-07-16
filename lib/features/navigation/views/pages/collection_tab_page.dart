import 'package:Prism/features/category_feed/views/pages/collection_screen.dart';
import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';

@RoutePage()
class CollectionTabPage extends StatelessWidget {
  const CollectionTabPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Color(0xFF050506),
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Padding(
              padding: EdgeInsets.fromLTRB(18, 14, 18, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    'Browse',
                    style: TextStyle(
                      color: Colors.white,
                      fontFamily: 'Satoshi',
                      fontSize: 34,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Explore every wallpaper category.',
                    style: TextStyle(
                      color: Colors.white70,
                      fontFamily: 'Satoshi',
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(child: CollectionScreen()),
          ],
        ),
      ),
    );
  }
}
