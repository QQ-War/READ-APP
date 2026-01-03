package com.readapp.ui.screens

import androidx.compose.material.icons.filled.Book
import androidx.compose.material.icons.filled.List
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import android.widget.Toast
import android.content.Intent
import android.content.ClipData
import androidx.navigation.NavController
import androidx.navigation.NavDestination.Companion.hierarchy
import androidx.navigation.NavGraph.Companion.findStartDestination
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.currentBackStackEntryAsState
import androidx.navigation.compose.rememberNavController
import com.readapp.Screen
import com.readapp.viewmodel.BookViewModel

@Composable
fun MainScreen(
    mainNavController: NavController,
    bookViewModel: BookViewModel
) {
    val localNavController = rememberNavController()
    val context = LocalContext.current
    
    Scaffold(
        bottomBar = {
            NavigationBar {
                val navBackStackEntry by localNavController.currentBackStackEntryAsState()
                val currentDestination = navBackStackEntry?.destination

                val items = listOf(
                    BottomNavItem.Bookshelf,
                    BottomNavItem.BookSource,
                    BottomNavItem.Settings
                )

                items.forEach { screen ->
                    NavigationBarItem(
                        icon = { Icon(screen.icon, contentDescription = null) },
                        label = { Text(screen.title) },
                        selected = currentDestination?.hierarchy?.any { it.route == screen.route } == true,
                        onClick = {
                            localNavController.navigate(screen.route) {
                                popUpTo(localNavController.graph.findStartDestination().id) {
                                    saveState = true
                                }
                                launchSingleTop = true
                                restoreState = true
                            }
                        }
                    )
                }
            }
        }
    ) { innerPadding ->
        Box(modifier = Modifier.padding(innerPadding)) {
            NavHost(localNavController, startDestination = BottomNavItem.Bookshelf.route) {
                composable(BottomNavItem.Bookshelf.route) {
                    // Pass the main NavController to allow navigation to Reading
                    BookshelfScreen(
                        mainNavController = mainNavController,
                        bookViewModel = bookViewModel
                    )
                }
                composable(BottomNavItem.BookSource.route) {
                    SourceListScreen(
                        onNavigateToEdit = { id ->
                            mainNavController.navigate(Screen.SourceEdit.createRoute(id))
                        },
                        onNavigateToSearch = { source ->
                            mainNavController.navigate(Screen.BookSearch.createRoute(source))
                        }
                    )
                }
                composable(BottomNavItem.Settings.route) {
                    val serverAddress by bookViewModel.serverAddress.collectAsState()
                    val username by bookViewModel.username.collectAsState()
                    val selectedTtsEngine by bookViewModel.selectedTtsEngine.collectAsState()
                    val useSystemTts by bookViewModel.useSystemTts.collectAsState()
                    val systemVoiceId by bookViewModel.systemVoiceId.collectAsState()
                    val narrationTtsEngine by bookViewModel.narrationTtsEngine.collectAsState()
                    val dialogueTtsEngine by bookViewModel.dialogueTtsEngine.collectAsState()
                    val speakerTtsMapping by bookViewModel.speakerTtsMapping.collectAsState()
                    val availableTtsEngines by bookViewModel.availableTtsEngines.collectAsState()
                    val speechSpeed by bookViewModel.speechSpeed.collectAsState()
                    val preloadCount by bookViewModel.preloadCount.collectAsState()
                    val loggingEnabled by bookViewModel.loggingEnabled.collectAsState()
                    val bookshelfSortByRecent by bookViewModel.bookshelfSortByRecent.collectAsState()
                    val readingMode by bookViewModel.readingMode.collectAsState()

                    SettingsScreen(
                        serverAddress = serverAddress,
                        username = username,
                        selectedTtsEngine = selectedTtsEngine,
                        useSystemTts = useSystemTts,
                        systemVoiceId = systemVoiceId,
                        narrationTtsEngine = narrationTtsEngine,
                        dialogueTtsEngine = dialogueTtsEngine,
                        speakerTtsMapping = speakerTtsMapping,
                        availableTtsEngines = availableTtsEngines,
                        speechSpeed = speechSpeed,
                        preloadCount = preloadCount,
                        loggingEnabled = loggingEnabled,
                        bookshelfSortByRecent = bookshelfSortByRecent,
                        readingMode = readingMode,
                        onReadingModeChange = bookViewModel::updateReadingMode,
                        onServerAddressChange = { bookViewModel.updateServerAddress(it) },
                        onSelectTtsEngine = { bookViewModel.selectTtsEngine(it) },
                        onUseSystemTtsChange = { bookViewModel.updateUseSystemTts(it) },
                        onSystemVoiceIdChange = { bookViewModel.updateSystemVoiceId(it) },
                        onSelectNarrationTtsEngine = { bookViewModel.selectNarrationTtsEngine(it) },
                        onSelectDialogueTtsEngine = { bookViewModel.selectDialogueTtsEngine(it) },
                        onAddSpeakerMapping = { name, ttsId -> bookViewModel.updateSpeakerMapping(name, ttsId) },
                        onRemoveSpeakerMapping = { name -> bookViewModel.removeSpeakerMapping(name) },
                        onReloadTtsEngines = { bookViewModel.loadTtsEngines() },
                        onSpeechSpeedChange = { bookViewModel.updateSpeechSpeed(it) },
                        onPreloadCountChange = { bookViewModel.updatePreloadCount(it) },
                        onClearCache = { bookViewModel.clearCache() },
                        onExportLogs = {
                            val uri = bookViewModel.exportLogs(context)
                            if (uri == null) {
                                Toast.makeText(context, "No logs to export", Toast.LENGTH_SHORT).show()
                            } else {
                                val shareIntent = Intent(Intent.ACTION_SEND).apply {
                                    type = "text/plain"
                                    putExtra(Intent.EXTRA_STREAM, uri)
                                    clipData = ClipData.newRawUri("logs", uri)
                                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                                }
                                context.startActivity(Intent.createChooser(shareIntent, "导出日志"))
                            }
                        },
                        onClearLogs = {
                            bookViewModel.clearLogs()
                            Toast.makeText(context, "Logs cleared", Toast.LENGTH_SHORT).show()
                        },
                        onLoggingEnabledChange = { enabled ->
                            bookViewModel.updateLoggingEnabled(enabled)
                        },
                        onBookshelfSortByRecentChange = { enabled ->
                            bookViewModel.updateBookshelfSortByRecent(enabled)
                        },
                        onNavigateToReplaceRules = {
                            mainNavController.navigate(Screen.ReplaceRules.route)
                        },
                        onLogout = {
                            bookViewModel.logout()
                            mainNavController.navigate(Screen.Login.route) {
                                popUpTo(0)
                                launchSingleTop = true
                            }
                        },
                        onNavigateBack = {
                            // Back is handled by TabView navigation or system back
                        }
                    )
                }
            }
        }
    }
}

sealed class BottomNavItem(val route: String, val title: String, val icon: androidx.compose.ui.graphics.vector.ImageVector) {
    object Bookshelf : BottomNavItem(Screen.Bookshelf.route, "书架", Icons.Default.Book)
    object BookSource : BottomNavItem(Screen.BookSource.route, "书源", Icons.Default.List)
    object Settings : BottomNavItem(Screen.Settings.route, "设置", Icons.Default.Settings)
}

