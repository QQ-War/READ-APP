// MainActivity.kt - 主活动（导航和整体布局）
package com.readapp

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
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
    val bookViewModel: BookViewModel = viewModel(factory = BookViewModel.Factory)

    val isLoggedIn = bookViewModel.accessToken.isNotBlank()

    Scaffold { paddingValues ->
        NavHost(
            navController = navController,
            startDestination = if (isLoggedIn) Screen.Bookshelf.route else Screen.Login.route,
            modifier = Modifier.padding(paddingValues)
        ) {
            composable(Screen.Login.route) {
                LoginScreen(
                    viewModel = bookViewModel,
                    onLoginSuccess = {
                        navController.navigate(Screen.Bookshelf.route) {
                            popUpTo(Screen.Login.route) { inclusive = true }
                        }
                    }
                )
            }

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
            
            composable(Screen.Reading.route) {
                bookViewModel.selectedBook?.let { book ->
                    ReadingScreen(
                        book = book,
                        chapters = bookViewModel.chapters,
                        currentChapterIndex = bookViewModel.currentChapterIndex,
                        content = bookViewModel.currentChapterContent,
                        isContentLoading = bookViewModel.isContentLoading,
                        onLoadContent = { bookViewModel.loadCurrentChapterContent() },
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
                            navController.navigate(Screen.Reading.route)
                        },
                        onExit = {
                            navController.popBackStack()
                        }
                    )
                }
            }
            
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
                    onLogout = { bookViewModel.logout() }
                )
            }
        }
    }
}

// 导航路由
sealed class Screen(val route: String) {
    object Login : Screen("login")
    object Bookshelf : Screen("bookshelf")
    object Reading : Screen("reading")
    object Player : Screen("player")
    object Settings : Screen("settings")
}
