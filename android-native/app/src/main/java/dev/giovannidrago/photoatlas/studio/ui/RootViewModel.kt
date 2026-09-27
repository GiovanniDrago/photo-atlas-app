package dev.giovannidrago.photoatlas.studio.ui

import androidx.lifecycle.ViewModel
import dagger.hilt.android.lifecycle.HiltViewModel
import dev.giovannidrago.photoatlas.studio.domain.auth.AuthRepository
import dev.giovannidrago.photoatlas.studio.ui.bootstrap.BootstrapController
import javax.inject.Inject

@HiltViewModel
class RootViewModel @Inject constructor(
	val bootstrap: BootstrapController,
	val auth: AuthRepository,
) : ViewModel()
