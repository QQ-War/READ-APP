package com.readapp.android

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.viewModels
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.rememberNavController
import com.readapp.android.ui.ReadApp
import com.readapp.android.ui.ReadViewModel
import com.readapp.android.ui.ReadViewModelFactory
import com.readapp.android.ui.theme.ReadAppTheme

class MainActivity : ComponentActivity() {
    private val viewModel: ReadViewModel by viewModels {
        ReadViewModelFactory(applicationContext)
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent {
            val navController = rememberNavController()
            val uiState by viewModel.uiState.collectAsState()

            ReadAppTheme {
                NavHost(
                    navController = navController,
                    startDestination = if (uiState.isLoggedIn) "books" else "login"
                ) {
                    composable("login") {
                        ReadApp(
                            uiState = uiState,
                            onLogin = { user, pass -> viewModel.login(user, pass) },
                            onServerChange = { server, public -> viewModel.updateServers(server, public) },
                            onNavigateBooks = { navController.navigate("books") { popUpTo("login") { inclusive = true } } },
                            onRefreshBooks = { viewModel.fetchBooks() },
                            onBookSelected = {},
                            onChapterSelect = {},
                            onToggleTts = {},
                            onTtsEngineSelect = {},
                            onSpeechRateChange = {},
                            onPreloadSegmentsChange = {},
                            onBackToBooks = {},
                            onFontScaleChange = { viewModel.updateFontScale(it) },
                            onLineSpacingChange = { viewModel.updateLineSpacing(it) },
                            onSortByRecentChange = { viewModel.setSortByRecent(it) },
                            onSortAscendingChange = { viewModel.setSortAscending(it) },
                            onSearchChange = { viewModel.updateSearchQuery(it) },
                            onReverseChaptersChange = { viewModel.setReverseChapterList(it) },
                            onClearCaches = { viewModel.clearLocalCaches() },
                            onParagraphJump = {},
                            onToggleImmersive = {}
                        )
                    }
                    composable("books") {
                        ReadApp(
                            uiState = uiState,
                            onLogin = { _, _ -> },
                            onServerChange = { server, public -> viewModel.updateServers(server, public) },
                            onNavigateBooks = {},
                            onRefreshBooks = { viewModel.fetchBooks() },
                            onBookSelected = { book -> viewModel.selectBook(book) },
                            onChapterSelect = { index -> viewModel.openChapter(index) },
                            onToggleTts = { viewModel.toggleSpeaking() },
                            onTtsEngineSelect = { viewModel.updateSelectedTts(it) },
                            onSpeechRateChange = { viewModel.updateSpeechRate(it) },
                            onPreloadSegmentsChange = { viewModel.updatePreloadSegments(it) },
                            onBackToBooks = { viewModel.exitReader() },
                            onFontScaleChange = { viewModel.updateFontScale(it) },
                            onLineSpacingChange = { viewModel.updateLineSpacing(it) },
                            onSortByRecentChange = { viewModel.setSortByRecent(it) },
                            onSortAscendingChange = { viewModel.setSortAscending(it) },
                            onSearchChange = { viewModel.updateSearchQuery(it) },
                            onReverseChaptersChange = { viewModel.setReverseChapterList(it) },
                            onClearCaches = { viewModel.clearLocalCaches() },
                            onParagraphJump = { viewModel.jumpToParagraph(it) },
                            onToggleImmersive = { viewModel.toggleImmersiveMode() }
                        )
                    }
                }
            }
        }
    }
}
