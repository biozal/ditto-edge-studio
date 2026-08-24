package com.costoda.dittoedgestudio.viewmodel

import com.costoda.dittoedgestudio.data.preferences.AppPreferencesGateway
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import org.junit.After
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class SettingsViewModelTest {

    private val testDispatcher = StandardTestDispatcher()

    @Before
    fun setUp() {
        Dispatchers.setMain(testDispatcher)
    }

    @After
    fun tearDown() {
        Dispatchers.resetMain()
    }

    @Test
    fun `setMetricsEnabled writes through to the preferences gateway`() = runTest {
        val fake = FakePrefs(initial = true)
        val vm = SettingsViewModel(fake)

        vm.setMetricsEnabled(false)
        advanceUntilIdle()

        assertFalse(fake.metricsEnabledValue)
    }

    @Test
    fun `metricsEnabled flow reflects gateway value`() = runTest {
        val fake = FakePrefs(initial = false)
        val vm = SettingsViewModel(fake)

        val job = launch { vm.metricsEnabled.collect { } }
        advanceUntilIdle()

        assertFalse(vm.metricsEnabled.value)
        job.cancel()
    }

    @Test
    fun `setPresenceSplitView writes through to the preferences gateway`() = runTest {
        val fake = FakePrefs(initial = true)
        val vm = SettingsViewModel(fake)

        vm.setPresenceSplitView(true)
        advanceUntilIdle()

        assertTrue(fake.presenceSplitViewValue)
    }

    private class FakePrefs(initial: Boolean) : AppPreferencesGateway {
        private val _metricsEnabled = MutableStateFlow(initial)
        override val metricsEnabled = _metricsEnabled
        val metricsEnabledValue: Boolean get() = _metricsEnabled.value
        override suspend fun setMetricsEnabled(enabled: Boolean) {
            _metricsEnabled.value = enabled
        }

        private val _presenceSplitView = MutableStateFlow(false)
        override val presenceSplitView = _presenceSplitView
        val presenceSplitViewValue: Boolean get() = _presenceSplitView.value
        override suspend fun setPresenceSplitView(enabled: Boolean) {
            _presenceSplitView.value = enabled
        }

        private val _lastOpenDatabaseId = MutableStateFlow<Long?>(null)
        override val lastOpenDatabaseId = _lastOpenDatabaseId
        override suspend fun setLastOpenDatabaseId(id: Long?) {
            _lastOpenDatabaseId.value = id
        }

        private val _showWelcome = MutableStateFlow(true)
        override val showWelcomeOnNewDatabase = _showWelcome
        override suspend fun setShowWelcomeOnNewDatabase(enabled: Boolean) {
            _showWelcome.value = enabled
        }
    }
}
