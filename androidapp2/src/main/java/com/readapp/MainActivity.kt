// MainActivity.kt - 主活动（导航和整体布局）
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
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.unit.dp
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.navigation.NavController
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.currentBackStackEntryAsState
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
    
    // 判断是否需要显示底部导航栏
    val currentRoute = navController.currentBackStackEntryAsState().value?.destination?.route
    val showBottomBar = currentRoute in listOf(
        Screen.Bookshelf.route,
        Screen.Reading.route,
        Screen.Player.route,
        Screen.Settings.route
    )
    
    Scaffold(
        bottomBar = {
            if (showBottomBar) {
                BottomNavigationBar(navController = navController)
            }
        }
    ) { paddingValues ->
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
                    }
                )
            }
            
            composable(Screen.Reading.route) {
                bookViewModel.selectedBook?.let { book ->
                    ReadingScreen(
                        book = book,
                        chapters = bookViewModel.chapters,
                        currentChapterIndex = bookViewModel.currentChapterIndex,
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

@Composable
fun BottomNavigationBar(navController: NavController) {
    val items = listOf(
        BottomNavItem.Bookshelf,
        BottomNavItem.Reading,
        BottomNavItem.Player,
        BottomNavItem.Settings
    )
    
    val currentRoute = navController.currentBackStackEntryAsState().value?.destination?.route
    
    NavigationBar(
        containerColor = MaterialTheme.colorScheme.surface,
        tonalElevation = 8.dp
    ) {
        items.forEach { item ->
            NavigationBarItem(
                icon = {
                    Icon(
                        imageVector = item.icon,
                        contentDescription = item.title
                    )
                },
                label = {
                    Text(
                        text = item.title,
                        style = MaterialTheme.typography.labelSmall
                    )
                },
                selected = currentRoute == item.route,
                onClick = {
                    if (currentRoute != item.route) {
                        navController.navigate(item.route) {
                            // 避免多次点击造成多个实例
                            launchSingleTop = true
                            // 返回到起始目的地时恢复状态
                            restoreState = true
                        }
                    }
                },
                colors = NavigationBarItemDefaults.colors(
                    selectedIconColor = MaterialTheme.colorScheme.primary,
                    selectedTextColor = MaterialTheme.colorScheme.primary,
                    unselectedIconColor = MaterialTheme.colorScheme.onSurfaceVariant,
                    unselectedTextColor = MaterialTheme.colorScheme.onSurfaceVariant
                )
            )
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

// 底部导航项
sealed class BottomNavItem(
    val route: String,
    val title: String,
    val icon: ImageVector
) {
    object Bookshelf : BottomNavItem(
        route = Screen.Bookshelf.route,
        title = "书架",
        icon = Icons.Default.Home
    )
    
    object Reading : BottomNavItem(
        route = Screen.Reading.route,
        title = "阅读",
        icon = Icons.Default.Book
    )
    
    object Player : BottomNavItem(
        route = Screen.Player.route,
        title = "听书",
        icon = Icons.Default.VolumeUp
    )
    
    object Settings : BottomNavItem(
        route = Screen.Settings.route,
        title = "设置",
        icon = Icons.Default.Settings
    )
}
