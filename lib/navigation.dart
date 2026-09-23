import 'package:flutter/material.dart';

/// Navigator of the whole app, used by widgets living above it (the backup
/// banner sits in the MaterialApp builder, outside the Navigator).
final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();
