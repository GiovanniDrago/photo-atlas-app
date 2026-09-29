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
import androidx.compose.foundation.layout.Box
import androidx.compose.material3.TopAppBar
import androidx.compose.ui.Alignment
import androidx.compose.material3.ExtendedFloatingActionButton
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.res.stringResource
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.navigation.NavGraph.Companion.findStartDestination
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.currentBackStackEntryAsState
import androidx.navigation.compose.rememberNavController
import dev.giovannidrago.photoatlas.studio.R
import dev.giovannidrago.photoatlas.studio.domain.auth.AuthRepository
import androidx.navigation.NavType
import androidx.navigation.navArgument
import dev.giovannidrago.photoatlas.studio.ui.albums.AlbumsViewModel
import dev.giovannidrago.photoatlas.studio.ui.screens.albums.AlbumEditScreen
import dev.giovannidrago.photoatlas.studio.ui.screens.albums.AlbumsScreen
import dev.giovannidrago.photoatlas.studio.ui.collections.CollectionsViewModel
import dev.giovannidrago.photoatlas.studio.ui.screens.collections.FolderHeader
import dev.giovannidrago.photoatlas.studio.ui.screens.collections.CollectionsScreen
import dev.giovannidrago.photoatlas.studio.ui.screens.timeline.TimelineScreen
import dev.giovannidrago.photoatlas.studio.ui.screens.BackupScreen
import dev.giovannidrago.photoatlas.studio.ui.screens.gallery.GalleryScreen
import dev.giovannidrago.photoatlas.studio.ui.screens.map.MapScreen
import dev.giovannidrago.photoatlas.studio.ui.screens.PlaceholderScreen
import dev.giovannidrago.photoatlas.studio.ui.screens.settings.SettingsScreen
import dev.giovannidrago.photoatlas.studio.ui.settings.SettingsViewModel

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
const val TimelineRoute = "timeline"
const val FolderRoute = "folder/{folderAlbumId}"
const val AlbumRoute = "album/{userAlbumId}"
const val AlbumEditRoute = "albumEdit?albumId={albumId}"

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun StudioApp(auth: AuthRepository) {
	val navController = rememberNavController()
	val backStackEntry by navController.currentBackStackEntryAsState()
	val currentRoute = backStackEntry?.destination?.route
	val currentTab = StudioTab.entries.firstOrNull { it.route == currentRoute }
	val albumsViewModel: AlbumsViewModel = hiltViewModel()
	val collectionsViewModel: CollectionsViewModel = hiltViewModel()

	Scaffold(
		containerColor = MaterialTheme.colorScheme.background,
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
					when (tab) {
						StudioTab.Map -> MapScreen()

						StudioTab.Gallery -> GalleryScreen(albumsViewModel = albumsViewModel)

						StudioTab.Collections -> CollectionsScreen(
							viewModel = collectionsViewModel,
							onOpenTimeline = { navController.navigate(TimelineRoute) },
							onOpenFolder = { folder ->
								navController.navigate("folder/${folder.id}")
							},
						)

						StudioTab.Albums -> AlbumsScreen(
							viewModel = albumsViewModel,
							onOpenAlbum = { album -> navController.navigate("album/${album.id}") },
							onEditAlbum = { album ->
								navController.navigate("albumEdit?albumId=${album.id}")
							},
							onCreateSmart = { navController.navigate("albumEdit") },
						)

						StudioTab.Settings -> SettingsScreen(
							auth = auth,
							viewModel = hiltViewModel<SettingsViewModel>(),
						)

						else -> PlaceholderTabScreen(tab)
					}
				}
			}
			composable(BackupRoute) {
				BackupScreen(onBack = { navController.popBackStack() })
			}
			composable(TimelineRoute) {
				TimelineScreen(
					albumsViewModel = albumsViewModel,
					onBack = { navController.popBackStack() },
				)
			}
			composable(
				route = FolderRoute,
				arguments = listOf(navArgument("folderAlbumId") { type = NavType.StringType }),
			) { entry ->
				val folderId = entry.arguments?.getString("folderAlbumId").orEmpty()
				GalleryScreen(
					albumsViewModel = albumsViewModel,
					onBack = { navController.popBackStack() },
					header = {
						FolderHeader(folderId = folderId, viewModel = collectionsViewModel)
					},
				)
			}
			composable(
				route = AlbumRoute,
				arguments = listOf(navArgument("userAlbumId") { type = NavType.StringType }),
			) {
				// The gallery view model reads the route argument from its
				// SavedStateHandle.
				GalleryScreen(
					albumsViewModel = albumsViewModel,
					onBack = { navController.popBackStack() },
					onEditAlbum = { id -> navController.navigate("albumEdit?albumId=$id") },
				)
			}
			composable(
				route = AlbumEditRoute,
				arguments = listOf(
					navArgument("albumId") {
						type = NavType.StringType
						nullable = true
						defaultValue = null
					},
				),
			) { entry ->
				val albumId = entry.arguments?.getString("albumId")
				AlbumEditScreen(
					viewModel = albumsViewModel,
					albumId = albumId,
					onDone = { navController.popBackStack() },
					onBack = { navController.popBackStack() },
				)
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

/** Placeholder tab with its own app bar, until its milestone ships. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun PlaceholderTabScreen(tab: StudioTab) {
	Scaffold(
		containerColor = MaterialTheme.colorScheme.background,
		topBar = { TopAppBar(title = { Text(stringResource(tab.labelRes)) }) },
	) { padding ->
		Box(modifier = Modifier.padding(padding)) {
			PlaceholderScreen(
				title = stringResource(tab.titleRes),
				text = stringResource(tab.descriptionRes),
				icon = tab.selectedIcon,
				milestone = tab.milestone,
			)
		}
	}
}
