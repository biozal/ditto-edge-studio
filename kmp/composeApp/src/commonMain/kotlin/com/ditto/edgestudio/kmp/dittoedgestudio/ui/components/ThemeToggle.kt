package com.ditto.edgestudio.kmp.dittoedgestudio.ui.components

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.ditto.edgestudio.kmp.dittoedgestudio.ui.theme.LocalThemeManager
import com.ditto.edgestudio.kmp.dittoedgestudio.ui.theme.ThemeMode

@Composable
fun ThemeToggleButton() {
    val themeManager = LocalThemeManager.current
    val currentTheme = themeManager.themeMode
    val isDarkTheme = themeManager.isDarkTheme()
    
    Row(
        modifier = Modifier
            .background(
                color = MaterialTheme.colorScheme.surface,
                shape = RoundedCornerShape(24.dp)
            )
            .padding(4.dp),
        horizontalArrangement = Arrangement.spacedBy(4.dp)
    ) {
        // Light mode button
        ThemeButton(
            selected = currentTheme == ThemeMode.LIGHT,
            onClick = { themeManager.setThemeMode(ThemeMode.LIGHT) },
            icon = "☀️",
            label = "Light"
        )
        
        // System mode button
        ThemeButton(
            selected = currentTheme == ThemeMode.SYSTEM,
            onClick = { themeManager.setThemeMode(ThemeMode.SYSTEM) },
            icon = "💻",
            label = "System"
        )
        
        // Dark mode button
        ThemeButton(
            selected = currentTheme == ThemeMode.DARK,
            onClick = { themeManager.setThemeMode(ThemeMode.DARK) },
            icon = "🌙",
            label = "Dark"
        )
    }
}

@Composable
private fun ThemeButton(
    selected: Boolean,
    onClick: () -> Unit,
    icon: String,
    label: String,
    modifier: Modifier = Modifier
) {
    val backgroundColor = if (selected) {
        MaterialTheme.colorScheme.primaryContainer
    } else {
        Color.Transparent
    }
    
    val contentColor = if (selected) {
        MaterialTheme.colorScheme.onPrimaryContainer
    } else {
        MaterialTheme.colorScheme.onSurfaceVariant
    }
    
    Row(
        modifier = modifier
            .clip(RoundedCornerShape(20.dp))
            .background(backgroundColor)
            .clickable { onClick() }
            .padding(horizontal = 12.dp, vertical = 8.dp),
        horizontalArrangement = Arrangement.spacedBy(6.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text(
            text = icon,
            fontSize = 16.sp
        )
        Text(
            text = label,
            fontSize = 12.sp,
            fontWeight = if (selected) FontWeight.Medium else FontWeight.Normal,
            color = contentColor
        )
    }
}

@Composable
fun QuickThemeToggle() {
    val themeManager = LocalThemeManager.current
    val isDarkTheme = themeManager.isDarkTheme()
    
    // Animated rotation for the icon
    val rotation by animateFloatAsState(
        targetValue = if (isDarkTheme) 180f else 0f,
        animationSpec = tween(300)
    )
    
    IconButton(
        onClick = { themeManager.toggleTheme() },
        modifier = Modifier
            .size(40.dp)
            .background(
                color = MaterialTheme.colorScheme.surfaceVariant,
                shape = CircleShape
            )
    ) {
        Text(
            text = if (isDarkTheme) "🌙" else "☀️",
            fontSize = 18.sp,
            modifier = Modifier.rotate(rotation)
        )
    }
}