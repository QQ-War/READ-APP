package com.readapp

import android.content.ClipData
import android.content.Intent
import android.os.Bundle
import android.widget.Toast
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.result.ActivityResultLauncher
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.rememberNavController
import androidx.navigation.navArgument
import com.readapp.ui.screens.BookshelfScreen
import com.readapp.ui.screens.BookDetailScreen
import com.readapp.ui.screens.CacheManagementScreen
import com.readapp.ui.screens.MainScreen
import com.readapp.ui.screens.LoginScreen
import com.readapp.ui.screens.ReadingScreen
import com.readapp.ui.screens.ReplaceRuleScreen
import com.readapp.ui.screens.SettingsScreen
import com.readapp.ui.screens.AccountSettingsScreen
import com.readapp.ui.screens.ReadingSettingsScreen
import com.readapp.ui.screens.TtsSettingsScreen
import com.readapp.ui.screens.ContentSettingsScreen
import com.readapp.ui.screens.DebugSettingsScreen
import com.readapp.ui.screens.PreferredSourcesScreen
import com.readapp.ui.screens.SourceExploreScreen
import com.readapp.ui.screens.SourceEditScreen
import com.readapp.ui.theme.ReadAppTheme
import com.readapp.viewmodel.BookViewModel
import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.navigation.NavType
import com.google.gson.Gson
import com.readapp.data.model.BookSource
import com.readapp.ui.screens.BookSearchScreen
import com.readapp.viewmodel.BookSearchViewModel
import com.readapp.ui.screens.TtsEngineManageScreen
import java.net.URLDecoder
import java.net.URLEncoder
import kotlin.text.Charsets.UTF_8

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        
        setContent {
            ReadAppTheme {
                ReadAppMain()
            }
        }
    }
}
@Composable
fun ReadAppMain() {
    val navController = rememberNavController()
    val bookViewModel: BookViewModel = viewModel()
    val accessToken by bookViewModel.accessToken.collectAsState()
    val isInitialized by bookViewModel.isInitialized.collectAsState()
    val isLoading by bookViewModel.isLoading.collectAsState()
    val context = LocalContext.current

    val importBookLauncher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.GetContent()
    ) { uri: Uri? ->
        uri?.let {
            bookViewModel.importBook(it)
        }
    }

    if (!isInitialized) {
        Box(
            modifier = Modifier.fillMaxSize(),
            contentAlignment = Alignment.Center
        ) {
            CircularProgressIndicator()
        }
        return
    }

    // 只有三个页面：书架、阅读（含听书）、设置
    Box(modifier = Modifier.fillMaxSize()) {
        NavHost(
            navController = navController,
            startDestination = if (accessToken.isBlank()) Screen.Login.route else Screen.Bookshelf.route
        ) {
            composable(Screen.Login.route) {
                LoginScreen(
                    viewModel = bookViewModel,
                    onLoginSuccess = {
                        navController.navigate(Screen.Bookshelf.route) {
                            popUpTo(Screen.Login.route) { inclusive = true }
                            launchSingleTop = true
                        }
                    }
                )
            }

            // 书架页面（主页），现在由 MainScreen 管理
            composable(Screen.Bookshelf.route) {
                MainScreen(
                    mainNavController = navController,
                    bookViewModel = bookViewModel
                )
            }

            composable(Screen.BookDetail.route) {
                val selectedBook by bookViewModel.selectedBook.collectAsState()
                val chapters by bookViewModel.chapters.collectAsState()
                val isChaptersLoading by bookViewModel.isChapterListLoading.collectAsState()
                val bookshelfBooks by bookViewModel.books.collectAsState()
                
                selectedBook?.let { book ->
                    val isInBookshelf = bookshelfBooks.any { it.bookUrl == book.bookUrl }
                    BookDetailScreen(
                        book = book,
                        chapters = chapters,
                        isChaptersLoading = isChaptersLoading,
                        isInBookshelf = isInBookshelf,
                        onAddToBookshelf = { bookViewModel.saveBookToBookshelf(book) },
                        onRemoveFromBookshelf = { bookViewModel.removeFromBookshelf(book) },
                        onNavigateBack = { navController.popBackStack() },
                        onStartReading = {
                            navController.navigate(Screen.Reading.route)
                        },
                        onChapterClick = { index ->
                            bookViewModel.setCurrentChapter(index)
                            navController.navigate(Screen.Reading.route)
                        },
                        onDownloadChapters = { start, end ->
                            bookViewModel.downloadChapters(start, end)
                        }
                    )
                }
            }

            // 阅读页面（集成听书功能）
            composable(Screen.Reading.route) {
                val selectedBook by bookViewModel.selectedBook.collectAsState()
                val chapters by bookViewModel.chapters.collectAsState()
                val currentChapterIndex by bookViewModel.currentChapterIndex.collectAsState()
                val currentChapterContent by bookViewModel.currentChapterContent.collectAsState()
                val isContentLoading by bookViewModel.isChapterContentLoading.collectAsState()
                val readingFontSize by bookViewModel.readingFontSize.collectAsState()
                val readingHorizontalPadding by bookViewModel.readingHorizontalPadding.collectAsState()
                val errorMessage by bookViewModel.errorMessage.collectAsState()
                val readingMode by bookViewModel.readingMode.collectAsState()
                val lockPageOnTTS by bookViewModel.lockPageOnTTS.collectAsState()

                // TTS 状态
                val isPlaying by bookViewModel.isPlaying.collectAsState()
                val isPaused by bookViewModel.isPaused.collectAsState()
                val showTtsControls by bookViewModel.showTtsControls.collectAsState()
                val currentPlayingParagraph by bookViewModel.currentParagraphIndex.collectAsState()
                val currentParagraphStartOffset by bookViewModel.currentParagraphStartOffset.collectAsState()
                val playbackProgress by bookViewModel.playbackProgress.collectAsState()
                val preloadedParagraphs by bookViewModel.preloadedParagraphs.collectAsState()

                selectedBook?.let { book ->
                    ReadingScreen(
                        book = book,
                        chapters = chapters,
                        currentChapterIndex = currentChapterIndex,
                        currentChapterContent = currentChapterContent,
                        isContentLoading = isContentLoading,
                        readingFontSize = readingFontSize,
                        readingHorizontalPadding = readingHorizontalPadding,
                        errorMessage = errorMessage,
                        readingMode = readingMode,
                        lockPageOnTTS = lockPageOnTTS,
                        onLockPageOnTTSChange = { bookViewModel.updateLockPageOnTTS(it) },
                        onClearError = { bookViewModel.clearError() },
                        onChapterClick = { index ->
                            bookViewModel.setCurrentChapter(index)
                        },
                        onLoadChapterContent = { index ->
                            bookViewModel.loadChapterContent(index)
                        },
                        onNavigateBack = {
                            // 如果正在播放，先停止
                            if (isPlaying) {
                                bookViewModel.stopTts()
                            }
                            navController.popBackStack()
                        },
                        // TTS 相关
                        isPlaying = isPlaying,
                        isPaused = isPaused,
                        showTtsControls = showTtsControls,
                        currentPlayingParagraph = currentPlayingParagraph,
                        currentParagraphStartOffset = currentParagraphStartOffset,
                        playbackProgress = playbackProgress,
                        preloadedParagraphs = preloadedParagraphs,
                        onPlayPauseClick = {
                            bookViewModel.togglePlayPause()
                        },
                        onStartListening = { startIndex, startOffset ->
                            bookViewModel.startTts(startIndex, startOffset)
                        },
                        onStopListening = {
                            bookViewModel.stopTts()
                        },
                        onPreviousParagraph = {
                            bookViewModel.previousParagraph()
                        },
                        onNextParagraph = {
                            bookViewModel.nextParagraph()
                        },
                        onReadingFontSizeChange = { size ->
                            bookViewModel.updateReadingFontSize(size)
                        },
                        onReadingHorizontalPaddingChange = { padding ->
                            bookViewModel.updateReadingHorizontalPadding(padding)
                        },
                        onExit = {
                            bookViewModel.saveBookProgress()
                        }
                    )
                }
            }

            // 设置页面
            composable(Screen.Settings.route) {
                val username by bookViewModel.username.collectAsState()
                SettingsScreen(
                    username = username,
                    onNavigateToSubSetting = { route -> navController.navigate(route) },
                    onNavigateBack = { navController.popBackStack() }
                )
            }

            composable(Screen.SettingsAccount.route) {
                val serverAddress by bookViewModel.serverAddress.collectAsState()
                val username by bookViewModel.username.collectAsState()
                AccountSettingsScreen(
                    serverAddress = serverAddress,
                    username = username,
                    onLogout = {
                        bookViewModel.logout()
                        navController.navigate(Screen.Login.route) {
                            popUpTo(0)
                            launchSingleTop = true
                        }
                    },
                    onNavigateBack = { navController.popBackStack() }
                )
            }

            composable(Screen.SettingsReading.route) {
                val readingMode by bookViewModel.readingMode.collectAsState()
                val readingFontSize by bookViewModel.readingFontSize.collectAsState()
                val readingHorizontalPadding by bookViewModel.readingHorizontalPadding.collectAsState()
                ReadingSettingsScreen(
                    readingMode = readingMode,
                    fontSize = readingFontSize,
                    horizontalPadding = readingHorizontalPadding,
                    onReadingModeChange = bookViewModel::updateReadingMode,
                    onFontSizeChange = bookViewModel::updateReadingFontSize,
                    onHorizontalPaddingChange = bookViewModel::updateReadingHorizontalPadding,
                    onClearCache = { bookViewModel.clearCache() },
                    onNavigateToCache = { navController.navigate(Screen.SettingsCache.route) },
                    onNavigateBack = { navController.popBackStack() }
                )
            }

            composable(Screen.SettingsTts.route) {
                val selectedTtsEngine by bookViewModel.selectedTtsEngine.collectAsState()
                val useSystemTts by bookViewModel.useSystemTts.collectAsState()
                val systemVoiceId by bookViewModel.systemVoiceId.collectAsState()
                val narrationTtsEngine by bookViewModel.narrationTtsEngine.collectAsState()
                val dialogueTtsEngine by bookViewModel.dialogueTtsEngine.collectAsState()
                val speakerTtsMapping by bookViewModel.speakerTtsMapping.collectAsState()
                val availableTtsEngines by bookViewModel.availableTtsEngines.collectAsState()
                val speechSpeed by bookViewModel.speechSpeed.collectAsState()
                val preloadCount by bookViewModel.preloadCount.collectAsState()
                val lockPageOnTTS by bookViewModel.lockPageOnTTS.collectAsState()

                TtsSettingsScreen(
                    selectedTtsEngine = selectedTtsEngine,
                    useSystemTts = useSystemTts,
                    systemVoiceId = systemVoiceId,
                    narrationTtsEngine = narrationTtsEngine,
                    dialogueTtsEngine = dialogueTtsEngine,
                    speakerTtsMapping = speakerTtsMapping,
                    availableTtsEngines = availableTtsEngines,
                    speechSpeed = speechSpeed,
                    preloadCount = preloadCount,
                    lockPageOnTTS = lockPageOnTTS,
                    onSelectTtsEngine = bookViewModel::selectTtsEngine,
                    onUseSystemTtsChange = bookViewModel::updateUseSystemTts,
                    onSystemVoiceIdChange = bookViewModel::updateSystemVoiceId,
                    onSelectNarrationTtsEngine = bookViewModel::selectNarrationTtsEngine,
                    onSelectDialogueTtsEngine = bookViewModel::selectDialogueTtsEngine,
                    onAddSpeakerMapping = bookViewModel::updateSpeakerMapping,
                    onRemoveSpeakerMapping = bookViewModel::removeSpeakerMapping,
                    onReloadTtsEngines = bookViewModel::loadTtsEngines,
                    onSpeechSpeedChange = bookViewModel::updateSpeechSpeed,
                    onPreloadCountChange = bookViewModel::updatePreloadCount,
                    onLockPageOnTTSChange = bookViewModel::updateLockPageOnTTS,
                    onNavigateToManage = { navController.navigate(Screen.SettingsTtsManage.route) },
                    onNavigateBack = { navController.popBackStack() }
                )
            }

            composable(Screen.SettingsTtsManage.route) {
                val engines by bookViewModel.availableTtsEngines.collectAsState()
                TtsEngineManageScreen(
                    engines = engines,
                    onAddEngine = bookViewModel::addTtsEngine,
                    onDeleteEngine = bookViewModel::deleteTtsEngine,
                    onNavigateBack = { navController.popBackStack() }
                )
            }

            composable(Screen.SettingsContent.route) {
                val bookshelfSortByRecent by bookViewModel.bookshelfSortByRecent.collectAsState()
                val searchOnlineEnabled by bookViewModel.searchSourcesFromBookshelf.collectAsState()
                val preferredSources by bookViewModel.preferredSearchSourceUrls.collectAsState()
                ContentSettingsScreen(
                    bookshelfSortByRecent = bookshelfSortByRecent,
                    searchOnlineEnabled = searchOnlineEnabled,
                    preferredSourcesCount = preferredSources.size,
                    onBookshelfSortByRecentChange = bookViewModel::updateBookshelfSortByRecent,
                    onSearchOnlineEnabledChange = bookViewModel::updateSearchSourcesFromBookshelf,
                    onNavigateToPreferredSources = { navController.navigate(Screen.SettingsPreferredSources.route) },
                    onNavigateToReplaceRules = { navController.navigate(Screen.ReplaceRules.route) },
                    onNavigateBack = { navController.popBackStack() }
                )
            }

            composable(Screen.SettingsPreferredSources.route) {
                val availableSources by bookViewModel.availableBookSources.collectAsState()
                val preferredSources by bookViewModel.preferredSearchSourceUrls.collectAsState()
                PreferredSourcesScreen(
                    availableSources = availableSources,
                    preferredUrls = preferredSources,
                    onToggleSource = bookViewModel::togglePreferredSearchSource,
                    onClearAll = bookViewModel::clearPreferredSearchSources,
                    onNavigateBack = { navController.popBackStack() }
                )
            }

            composable(Screen.SettingsDebug.route) {
                val loggingEnabled by bookViewModel.loggingEnabled.collectAsState()
                val context = LocalContext.current
                DebugSettingsScreen(
                    loggingEnabled = loggingEnabled,
                    onLoggingEnabledChange = bookViewModel::updateLoggingEnabled,
                    onExportLogs = {
                        val uri = bookViewModel.exportLogs(context)
                        if (uri != null) {
                            val shareIntent = Intent(Intent.ACTION_SEND).apply {
                                type = "text/plain"
                                putExtra(Intent.EXTRA_STREAM, uri)
                                clipData = ClipData.newRawUri("logs", uri)
                                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                            }
                            context.startActivity(Intent.createChooser(shareIntent, "导出日志"))
                        }
                    },
                    onClearLogs = { bookViewModel.clearLogs() },
                    onClearCache = { bookViewModel.clearCache() },
                    logCount = 0, // Should be fetched from LogManager
                    onNavigateBack = { navController.popBackStack() }
                )
            }

            composable(Screen.SettingsCache.route) {
                CacheManagementScreen(
                    bookViewModel = bookViewModel,
                    onNavigateBack = { navController.popBackStack() }
                )
            }
            
            // 净化规则管理页面
            composable(Screen.ReplaceRules.route) {
                ReplaceRuleScreen(
                    onNavigateBack = { navController.popBackStack() }
                )
            }
            
            // 书源编辑页面
            composable(
                route = Screen.SourceEdit.route,
                arguments = listOf(navArgument("id") { nullable = true; defaultValue = null })
            ) { backStackEntry ->
                val id = backStackEntry.arguments?.getString("id")
                SourceEditScreen(
                    sourceId = id,
                    onNavigateBack = { navController.popBackStack() }
                )
            }

            composable(
                route = Screen.SourceExplore.route,
                arguments = listOf(
                    navArgument("sourceUrl") { type = NavType.StringType },
                    navArgument("sourceName") { type = NavType.StringType },
                    navArgument("ruleFindUrl") { type = NavType.StringType },
                    navArgument("categoryName") { type = NavType.StringType }
                )
            ) { backStackEntry ->
                val sourceUrl = URLDecoder.decode(backStackEntry.arguments?.getString("sourceUrl") ?: "", UTF_8.name())
                val sourceName = URLDecoder.decode(backStackEntry.arguments?.getString("sourceName") ?: "", UTF_8.name())
                val ruleFindUrl = URLDecoder.decode(backStackEntry.arguments?.getString("ruleFindUrl") ?: "", UTF_8.name())
                val categoryName = URLDecoder.decode(backStackEntry.arguments?.getString("categoryName") ?: "", UTF_8.name())
                
                SourceExploreScreen(
                    sourceUrl = sourceUrl,
                    sourceName = sourceName,
                    ruleFindUrl = ruleFindUrl,
                    categoryName = categoryName,
                    onNavigateToDetail = { navController.navigate(Screen.BookDetail.route) },
                    onNavigateBack = { navController.popBackStack() }
                )
            }

            composable(
                route = Screen.BookSearch.route,
                arguments = listOf(navArgument("bookSourceJson") { type = NavType.StringType })
            ) { backStackEntry ->
                val json = backStackEntry.arguments?.getString("bookSourceJson")?.let {
                    URLDecoder.decode(it, UTF_8.name())
                }
                val bookSource = Gson().fromJson(json, BookSource::class.java)
                val searchViewModel: BookSearchViewModel = viewModel(
                    factory = BookSearchViewModel.Factory(
                        bookSource = bookSource,
                        repository = bookViewModel.repository,
                        userPreferences = bookViewModel.preferences
                    )
                )
                BookSearchScreen(
                    viewModel = searchViewModel,
                    onBack = { navController.popBackStack() }
                )
            }
        }

        if (isLoading && accessToken.isNotBlank()) {
            Box(
                modifier = Modifier.fillMaxSize(),
                contentAlignment = Alignment.TopEnd
            ) {
                CircularProgressIndicator(modifier = Modifier.padding(16.dp))
            }
        }
    }
}

// 导航路由定义
sealed class Screen(val route: String) {
    object Login : Screen("login")
    object Bookshelf : Screen("bookshelf")
    object BookDetail : Screen("book_detail")
    object Reading : Screen("reading")
    object Settings : Screen("settings")
    object SettingsAccount : Screen("settings_account")
    object SettingsReading : Screen("settings_reading")
    object SettingsTts : Screen("settings_tts")
    object SettingsTtsManage : Screen("settings_tts_manage")
    object SettingsContent : Screen("settings_content")
    object SettingsPreferredSources : Screen("settings_preferred_sources")
    object SettingsDebug : Screen("settings_debug")
    object SettingsCache : Screen("settings_cache")
    object ReplaceRules : Screen("replace_rules")
    object BookSource : Screen("book_source")
    object SourceEdit : Screen("source_edit?id={id}") {
        fun createRoute(id: String?) = if (id != null) "source_edit?id=$id" else "source_edit"
    }
    object SourceExplore : Screen("source_explore/{sourceUrl}/{sourceName}/{ruleFindUrl}/{categoryName}") {
        fun createRoute(sourceUrl: String, sourceName: String, ruleFindUrl: String, categoryName: String): String {
            val encodedSourceUrl = URLEncoder.encode(sourceUrl, UTF_8.name())
            val encodedSourceName = URLEncoder.encode(sourceName, UTF_8.name())
            val encodedRuleUrl = URLEncoder.encode(ruleFindUrl, UTF_8.name())
            val encodedCategoryName = URLEncoder.encode(categoryName, UTF_8.name())
            return "source_explore/$encodedSourceUrl/$encodedSourceName/$encodedRuleUrl/$encodedCategoryName"
        }
    }
    object BookSearch : Screen("book_search/{bookSourceJson}") {
        fun createRoute(bookSource: com.readapp.data.model.BookSource): String {
            val json = Gson().toJson(bookSource)
            val encodedJson = URLEncoder.encode(json, UTF_8.name())
            return "book_search/$encodedJson"
        }
    }
}
