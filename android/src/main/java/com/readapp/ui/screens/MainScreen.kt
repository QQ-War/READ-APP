package com.readapp.ui.screens

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Book
import androidx.compose.material.icons.filled.List
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material3.Icon
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
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
                        },
                        onNavigateToExplore = { sourceUrl, sourceName, ruleUrl, categoryName ->
                            mainNavController.navigate(Screen.SourceExplore.createRoute(sourceUrl, sourceName, ruleUrl, categoryName))
                        }
                    )
                }
                composable(BottomNavItem.Settings.route) {
                    val username by bookViewModel.username.collectAsState()
                    SettingsScreen(
                        username = username,
                        onNavigateToSubSetting = { route ->
                            mainNavController.navigate(route)
                        },
                        onNavigateBack = { }
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
