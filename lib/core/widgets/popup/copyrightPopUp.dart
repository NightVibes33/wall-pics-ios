import 'package:Prism/core/utils/url_launcher_compat.dart';
import 'package:flutter/material.dart';

class CopyrightPopUp extends StatelessWidget {
  final bool setup;
  final String shortlink;
  const CopyrightPopUp({required this.setup, required this.shortlink});
  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      title: Text(
        "LICENSE",
        style: Theme.of(context).textTheme.titleLarge!.copyWith(color: Theme.of(context).colorScheme.secondary),
      ),
      content: SingleChildScrollView(
        child: Text(
          setup == true
              ? "This setup is a property of their respective owner. You can use it for your personal use only. Any distribution or sharing is not allowed without the permission of the owner."
              : "This wallpaper is a property of their respective owner. You can use it for your personal use only. Any distribution or sharing is not allowed without the permission of the owner.",
          style: Theme.of(context).textTheme.titleLarge!.copyWith(color: Theme.of(context).colorScheme.secondary),
        ),
      ),
      actions: [
        MaterialButton(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
          color: Colors.transparent,
          onPressed: () {
            Navigator.pop(context);
            setup == true
                ? openPrismLink(
                    context,
                    "https://github.com/NightVibes33/wall-pics-ios/issues/new?title=Report%20setup&body=Link:%20$shortlink%0A%0ADescribe%20the%20issue%20below:",
                  )
                : openPrismLink(
                    context,
                    "https://github.com/NightVibes33/wall-pics-ios/issues/new?title=Report%20wallpaper&body=Link:%20$shortlink%0A%0ADescribe%20the%20issue%20below:",
                  );
          },
          child: Text(
            "REPORT",
            style: TextStyle(
              color: Theme.of(context).colorScheme.error == Colors.black
                  ? Colors.white
                  : Theme.of(context).colorScheme.error,
            ),
          ),
        ),
        MaterialButton(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
          color: Theme.of(context).colorScheme.error,
          onPressed: () {
            Navigator.pop(context);
          },
          child: Text("OK", style: TextStyle(color: Theme.of(context).colorScheme.secondary)),
        ),
      ],
      backgroundColor: Theme.of(context).primaryColor,
      actionsPadding: const EdgeInsets.fromLTRB(10, 0, 10, 0),
    );
  }
}
