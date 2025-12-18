// MainActivity.kt - 去掉独立播放器页面，集成到阅读页面
package com.readapp

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.runtime.*
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.rememberNavController
import com.readapp.ui.screens.*
import com.readapp.ui.theme.ReadAppTheme
import com.readapp.viewmodel.BookViewModel

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

    LaunchedEffect(accessToken) {
        if (accessToken.isBlank()) {
            navController.navigate(Screen.Login.route) {
                popUpTo(0)
                launchSingleTop = true
            }
        } else {
            navController.navigate(Screen.Bookshelf.route) {
                popUpTo(0)
                launchSingleTop = true
            }
        }
    }
    
    // 只有三个页面：书架、阅读（含听书）、设置
    NavHost(
        navController = navController,
        startDestination = Screen.Login.route
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
                onBookClick = { book ->
                    bookViewModel.selectBook(book)
                    navController.navigate(Screen.Reading.route)
                },
                onSearchQueryChange = { query ->
                    bookViewModel.searchBooks(query)
                },
                onSettingsClick = {
                    navController.navigate(Screen.Settings.route)
                }
            )
        }
        
        // 阅读页面（集成听书功能）
        composable(Screen.Reading.route) {
            val selectedBook by bookViewModel.selectedBook.collectAsState()
            val chapters by bookViewModel.chapters.collectAsState()
            val currentChapterIndex by bookViewModel.currentChapterIndex.collectAsState()
            val currentChapterContent by bookViewModel.currentChapterContent.collectAsState()
            
            // TTS 状态
            val isPlaying by bookViewModel.isPlaying.collectAsState()
            val currentPlayingParagraph by bookViewModel.currentParagraphIndex.collectAsState()
            val preloadedParagraphs by bookViewModel.preloadedParagraphs.collectAsState()
            
            selectedBook?.let { book ->
                ReadingScreen(
                    book = book,
                    chapters = chapters,
                    currentChapterIndex = currentChapterIndex,
                    currentChapterContent = currentChapterContent,
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
                    currentPlayingParagraph = currentPlayingParagraph,
                    preloadedParagraphs = preloadedParagraphs,
                    onPlayPauseClick = {
                        bookViewModel.togglePlayPause()
                    },
                    onStartListening = {
                        bookViewModel.startTts()
                    },
                    onStopListening = {
                        bookViewModel.stopTts()
                    },
                    onPreviousParagraph = {
                        bookViewModel.previousParagraph()
                    },
                    onNextParagraph = {
                        bookViewModel.nextParagraph()
                    }
                )
            }
        }
        
        // 设置页面
        composable(Screen.Settings.route) {
            val serverAddress by bookViewModel.serverAddress.collectAsState()
            val selectedTtsEngine by bookViewModel.selectedTtsEngine.collectAsState()
            val speechSpeed by bookViewModel.speechSpeed.collectAsState()
            val preloadCount by bookViewModel.preloadCount.collectAsState()
            
            SettingsScreen(
                serverAddress = serverAddress,
                selectedTtsEngine = selectedTtsEngine,
                speechSpeed = speechSpeed,
                preloadCount = preloadCount,
                onServerAddressChange = { bookViewModel.updateServerAddress(it) },
                onTtsEngineClick = { /* 显示引擎选择对话框 */ },
                onSpeechSpeedChange = { bookViewModel.updateSpeechSpeed(it) },
                onPreloadCountChange = { bookViewModel.updatePreloadCount(it) },
                onClearCache = { bookViewModel.clearCache() },
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
    }
}

// 导航路由定义（去掉 Player 页面）
sealed class Screen(val route: String) {
    object Login : Screen("login")
    object Bookshelf : Screen("bookshelf")
    object Reading : Screen("reading")
    object Settings : Screen("settings")
}
