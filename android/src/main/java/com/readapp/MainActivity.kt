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
import com.readapp.ui.screens.BookshelfScreen
import com.readapp.ui.screens.LoginScreen
import com.readapp.ui.screens.ReadingScreen
import com.readapp.ui.screens.ReplaceRuleScreen
import com.readapp.ui.screens.SettingsScreen
import com.readapp.ui.theme.ReadAppTheme
import com.readapp.viewmodel.BookViewModel
import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult

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

            // 书架页面（主页）
            composable(Screen.Bookshelf.route) {
                val books by bookViewModel.books.collectAsState()

                BookshelfScreen(
                    books = books,
                    isRefreshing = isLoading,
                    onRefresh = {
                        bookViewModel.refreshBooks()
                    },
                    onBookClick = { book ->
                        bookViewModel.selectBook(book)
                        navController.navigate(Screen.Reading.route)
                    },
                    onSearchQueryChange = { query ->
                        bookViewModel.searchBooks(query)
                    },
                    onSettingsClick = {
                        navController.navigate(Screen.Settings.route)
                    },
                    onImportClick = {
                        importBookLauncher.launch("*/*")
                    }
                )
            }

            // 阅读页面（集成听书功能）
            composable(Screen.Reading.route) {
                val selectedBook by bookViewModel.selectedBook.collectAsState()
                val chapters by bookViewModel.chapters.collectAsState()
                val currentChapterIndex by bookViewModel.currentChapterIndex.collectAsState()
                val currentChapterContent by bookViewModel.currentChapterContent.collectAsState()
                val isContentLoading by bookViewModel.isChapterContentLoading.collectAsState()
                val readingFontSize by bookViewModel.readingFontSize.collectAsState()
                val errorMessage by bookViewModel.errorMessage.collectAsState()
                val readingMode by bookViewModel.readingMode.collectAsState()

                // TTS 状态
                val isPlaying by bookViewModel.isPlaying.collectAsState()
                val isPlayingUi by bookViewModel.isPlayingUi.collectAsState()
                val currentPlayingParagraph by bookViewModel.currentParagraphIndex.collectAsState()
                val preloadedParagraphs by bookViewModel.preloadedParagraphs.collectAsState()

                selectedBook?.let { book ->
                    ReadingScreen(
                        book = book,
                        chapters = chapters,
                        currentChapterIndex = currentChapterIndex,
                        currentChapterContent = currentChapterContent,
                        isContentLoading = isContentLoading,
                        readingFontSize = readingFontSize,
                        errorMessage = errorMessage,
                        readingMode = readingMode,
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
                        isPlaying = isPlayingUi,
                        currentPlayingParagraph = currentPlayingParagraph,
                        preloadedParagraphs = preloadedParagraphs,
                        onPlayPauseClick = {
                            bookViewModel.togglePlayPause()
                        },
                        onStartListening = { startIndex ->
                            bookViewModel.startTts(startIndex)
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
                        onExit = {
                            bookViewModel.saveBookProgress()
                        }
                    )
                }
            }

            // 设置页面
            composable(Screen.Settings.route) {
                val serverAddress by bookViewModel.serverAddress.collectAsState()
                val username by bookViewModel.username.collectAsState()
                val selectedTtsEngine by bookViewModel.selectedTtsEngine.collectAsState()
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
                            Toast.makeText(context, "暂无日志可导出", Toast.LENGTH_SHORT).show()
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
                        Toast.makeText(context, "历史日志已清除", Toast.LENGTH_SHORT).show()
                    },
                    onLoggingEnabledChange = { enabled ->
                        bookViewModel.updateLoggingEnabled(enabled)
                    },
                    onBookshelfSortByRecentChange = { enabled ->
                        bookViewModel.updateBookshelfSortByRecent(enabled)
                    },
                    onNavigateToReplaceRules = {
                        navController.navigate(Screen.ReplaceRules.route)
                    },
                    onLogout = {
                        bookViewModel.logout()
                        navController.navigate(Screen.Login.route) {
                            popUpTo(0)
                            launchSingleTop = true
                        }
                    },
                    onNavigateBack = {
                        navController.popBackStack()
                    }
                )
            }
            
            // 净化规则管理页面
            composable(Screen.ReplaceRules.route) {
                ReplaceRuleScreen(
                    onNavigateBack = { navController.popBackStack() }
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
    object Reading : Screen("reading")
    object Settings : Screen("settings")
    object ReplaceRules : Screen("replace_rules")
}
