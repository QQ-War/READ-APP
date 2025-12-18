// MainActivity.kt - 简化的导航结构（只有书架主页）
package com.readapp

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.navigation.NavController
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
    
    // 简化的导航：只有书架、阅读、播放器、设置四个页面
    // 不使用底部导航栏
    NavHost(
        navController = navController,
        startDestination = Screen.Bookshelf.route
    ) {
        // 书架页面（主页）
        composable(Screen.Bookshelf.route) {
            BookshelfScreen(
                books = bookViewModel.books,
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
        
        // 阅读页面（点击书籍后进入）
        composable(Screen.Reading.route) {
            bookViewModel.selectedBook?.let { book ->
                ReadingScreen(
                    book = book,
                    chapters = bookViewModel.chapters,
                    currentChapterIndex = bookViewModel.currentChapterIndex,
                    currentChapterContent = bookViewModel.currentChapterContent,
                    onChapterClick = { index ->
                        bookViewModel.setCurrentChapter(index)
                    },
                    onStartListening = {
                        navController.navigate(Screen.Player.route)
                    },
                    onNavigateBack = {
                        navController.popBackStack()
                    }
                )
            }
        }
        
        // 播放器页面（听书模式）
        composable(Screen.Player.route) {
            bookViewModel.selectedBook?.let { book ->
                PlayerScreen(
                    book = book,
                    chapterTitle = bookViewModel.currentChapterTitle,
                    currentParagraph = bookViewModel.currentParagraph,
                    totalParagraphs = bookViewModel.totalParagraphs,
                    currentTime = bookViewModel.currentTime,
                    totalTime = bookViewModel.totalTime,
                    progress = bookViewModel.playbackProgress,
                    isPlaying = bookViewModel.isPlaying,
                    onPlayPauseClick = { bookViewModel.togglePlayPause() },
                    onPreviousParagraph = { bookViewModel.previousParagraph() },
                    onNextParagraph = { bookViewModel.nextParagraph() },
                    onPreviousChapter = { bookViewModel.previousChapter() },
                    onNextChapter = { bookViewModel.nextChapter() },
                    onShowChapterList = {
                        navController.popBackStack()
                    },
                    onExit = {
                        navController.popBackStack()
                    }
                )
            }
        }
        
        // 设置页面（从书架右上角进入）
        composable(Screen.Settings.route) {
            SettingsScreen(
                serverAddress = bookViewModel.serverAddress,
                selectedTtsEngine = bookViewModel.selectedTtsEngine,
                speechSpeed = bookViewModel.speechSpeed,
                preloadCount = bookViewModel.preloadCount,
                onServerAddressChange = { bookViewModel.updateServerAddress(it) },
                onTtsEngineClick = { /* 显示引擎选择对话框 */ },
                onSpeechSpeedChange = { bookViewModel.updateSpeechSpeed(it) },
                onPreloadCountChange = { bookViewModel.updatePreloadCount(it) },
                onClearCache = { bookViewModel.clearCache() },
                onLogout = { bookViewModel.logout() },
                onNavigateBack = {
                    navController.popBackStack()
                }
            )
        }
    }
}

// 导航路由定义
sealed class Screen(val route: String) {
    object Bookshelf : Screen("bookshelf")
    object Reading : Screen("reading")
    object Player : Screen("player")
    object Settings : Screen("settings")
}
