package dev.giovannidrago.photoatlas.studio.ui

import androidx.annotation.StringRes
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Collections
import androidx.compose.material.icons.filled.PhotoAlbum
import androidx.compose.material.icons.filled.PhotoLibrary
import androidx.compose.material.icons.filled.Public
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.outlined.Collections
import androidx.compose.material.icons.outlined.PhotoAlbum
import androidx.compose.material.icons.outlined.PhotoLibrary
import androidx.compose.material.icons.outlined.Public
import androidx.compose.material.icons.outlined.Settings
import androidx.compose.material3.ExtendedFloatingActionButton
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.res.stringResource
import androidx.navigation.NavGraph.Companion.findStartDestination
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.currentBackStackEntryAsState
import androidx.navigation.compose.rememberNavController
import dev.giovannidrago.photoatlas.studio.BuildConfig
import dev.giovannidrago.photoatlas.studio.R
import dev.giovannidrago.photoatlas.studio.ui.screens.BackupScreen
import dev.giovannidrago.photoatlas.studio.ui.screens.PlaceholderScreen

/// Top-level destinations of the shell, in the same order as the Flutter app.
enum class StudioTab(
	val route: String,
	@StringRes val labelRes: Int,
	val icon: ImageVector,
	val selectedIcon: ImageVector,
	val milestone: String,
	@StringRes val titleRes: Int,
	@StringRes val descriptionRes: Int,
) {
	Map(
		route = "map",
		labelRes = R.string.tab_map,
		icon = Icons.Outlined.Public,
		selectedIcon = Icons.Filled.Public,
		milestone = "M4",
		titleRes = R.string.placeholder_map_title,
		descriptionRes = R.string.placeholder_map_text,
	),
	Collections(
		route = "collections",
		labelRes = R.string.tab_collections,
		icon = Icons.Outlined.Collections,
		selectedIcon = Icons.Filled.Collections,
		milestone = "M3",
		titleRes = R.string.placeholder_collections_title,
		descriptionRes = R.string.placeholder_collections_text,
	),
	Gallery(
		route = "gallery",
		labelRes = R.string.tab_gallery,
		icon = Icons.Outlined.PhotoLibrary,
		selectedIcon = Icons.Filled.PhotoLibrary,
		milestone = "M2",
		titleRes = R.string.placeholder_gallery_title,
		descriptionRes = R.string.placeholder_gallery_text,
	),
	Albums(
		route = "albums",
		labelRes = R.string.tab_albums,
		icon = Icons.Outlined.PhotoAlbum,
		selectedIcon = Icons.Filled.PhotoAlbum,
		milestone = "M3",
		titleRes = R.string.placeholder_albums_title,
		descriptionRes = R.string.placeholder_albums_text,
	),
	Settings(
		route = "settings",
		labelRes = R.string.tab_settings,
		icon = Icons.Outlined.Settings,
		selectedIcon = Icons.Filled.Settings,
		milestone = "M1",
		titleRes = R.string.placeholder_settings_title,
		descriptionRes = R.string.placeholder_settings_text,
	),
}

const val BackupRoute = "backup"

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun StudioApp() {
	val navController = rememberNavController()
	val backStackEntry by navController.currentBackStackEntryAsState()
	val currentRoute = backStackEntry?.destination?.route
	val currentTab = StudioTab.entries.firstOrNull { it.route == currentRoute }

	Scaffold(
		containerColor = MaterialTheme.colorScheme.background,
		topBar = {
			if (currentTab != null) {
				TopAppBar(
					title = {
						Text(
							text = stringResource(currentTab.labelRes),
							style = MaterialTheme.typography.titleLarge,
						)
					},
					colors = TopAppBarDefaults.topAppBarColors(
						containerColor = MaterialTheme.colorScheme.background,
						titleContentColor = MaterialTheme.colorScheme.onBackground,
					),
				)
			}
		},
		bottomBar = {
			if (currentTab != null) {
				StudioBottomBar(
					current = currentTab,
					onSelect = { tab ->
						navController.navigate(tab.route) {
							popUpTo(navController.graph.findStartDestination().id) {
								saveState = true
							}
							launchSingleTop = true
							restoreState = true
						}
					},
				)
			}
		},
		floatingActionButton = {
			if (currentTab != null) {
				ExtendedFloatingActionButton(
					onClick = { navController.navigate(BackupRoute) },
					icon = { Icon(Icons.Filled.Add, contentDescription = null) },
					text = { Text(stringResource(R.string.action_backup)) },
					containerColor = MaterialTheme.colorScheme.primaryContainer,
					contentColor = MaterialTheme.colorScheme.onPrimaryContainer,
				)
			}
		},
	) { innerPadding ->
		NavHost(
			navController = navController,
			startDestination = StudioTab.Map.route,
			modifier = Modifier.padding(innerPadding),
			enterTransition = {
				fadeIn(tween(220)) +
					slideInVertically(tween(220), initialOffsetY = { it / 24 })
			},
			exitTransition = { fadeOut(tween(150)) },
			popEnterTransition = { fadeIn(tween(220)) },
			popExitTransition = { fadeOut(tween(150)) },
		) {
			StudioTab.entries.forEach { tab ->
				composable(tab.route) {
					PlaceholderScreen(
						title = stringResource(tab.titleRes),
						text = stringResource(tab.descriptionRes),
						icon = tab.selectedIcon,
						milestone = tab.milestone,
						footer = if (tab == StudioTab.Settings) {
							stringResource(R.string.native_preview_version, BuildConfig.VERSION_NAME)
						} else {
							null
						},
					)
				}
			}
			composable(BackupRoute) {
				BackupScreen(onBack = { navController.popBackStack() })
			}
		}
	}
}

@Composable
private fun StudioBottomBar(
	current: StudioTab,
	onSelect: (StudioTab) -> Unit,
) {
	NavigationBar(containerColor = MaterialTheme.colorScheme.surfaceContainer) {
		StudioTab.entries.forEach { tab ->
			val selected = tab == current
			NavigationBarItem(
				selected = selected,
				onClick = { if (!selected) onSelect(tab) },
				icon = {
					Icon(
						imageVector = if (selected) tab.selectedIcon else tab.icon,
						contentDescription = null,
					)
				},
				label = { Text(stringResource(tab.labelRes), maxLines = 1) },
				alwaysShowLabel = true,
			)
		}
	}
}
