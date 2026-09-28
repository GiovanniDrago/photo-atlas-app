package dev.giovannidrago.photoatlas.studio.ui.screens.albums

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Clear
import androidx.compose.material.icons.filled.Event
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DatePicker
import androidx.compose.material3.DatePickerDialog
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.rememberDatePickerState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import dev.giovannidrago.photoatlas.studio.R
import dev.giovannidrago.photoatlas.studio.data.remote.AlbumDto
import dev.giovannidrago.photoatlas.studio.domain.gallery.AlbumRuleDraft
import dev.giovannidrago.photoatlas.studio.domain.gallery.AlbumRuleState
import dev.giovannidrago.photoatlas.studio.ui.albums.AlbumsViewModel
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneOffset
import java.time.format.DateTimeFormatter
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

private enum class DateField { TakenFrom, TakenTo, UploadedFrom, UploadedTo }

/** Smart-album builder: dates, type and a live matching-items preview. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AlbumEditScreen(
	viewModel: AlbumsViewModel,
	albumId: String?,
	onDone: (AlbumDto) -> Unit,
	onBack: () -> Unit,
) {
	val existing = remember(albumId) {
		albumId?.let { id -> viewModel.albums.value.firstOrNull { it.id == id } }
	}
	var name by remember { mutableStateOf(existing?.name.orEmpty()) }
	var rules by remember {
		mutableStateOf(AlbumRuleDraft.fromRules(existing?.rules))
	}
	var preview by remember { mutableStateOf<Int?>(null) }
	var previewing by remember { mutableStateOf(false) }
	var error by remember { mutableStateOf<String?>(null) }
	var saving by remember { mutableStateOf(false) }
	var picker by remember { mutableStateOf<DateField?>(null) }
	val scope = rememberCoroutineScope()
	val dateFormat = DateTimeFormatter.ISO_LOCAL_DATE

	LaunchedEffect(rules) {
		if (rules.isEmpty) {
			preview = 0
			return@LaunchedEffect
		}
		delay(400)
		previewing = true
		preview = runCatching { viewModel.previewRules(rules.toRules()) }.getOrNull() ?: preview
		previewing = false
	}

	fun save() {
		val clean = name.trim()
		when {
			clean.isEmpty() -> error = "albumNameRequired"
			rules.isEmpty -> error = "albumRulesRequired"
			else -> {
				error = null
				saving = true
				scope.launch {
					val saved = viewModel.save(
						name = clean,
						rules = rules.toRules(),
						albumId = albumId,
					)
					saving = false
					if (saved != null) onDone(saved)
				}
			}
		}
	}

	Scaffold(
		containerColor = MaterialTheme.colorScheme.background,
		topBar = {
			TopAppBar(
				title = {
					Text(
						stringResource(
							if (albumId == null) R.string.album_create_smart else R.string.album_edit_rules,
						),
					)
				},
				navigationIcon = {
					IconButton(onClick = onBack) {
						Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = null)
					}
				},
				actions = {
					TextButton(onClick = { save() }, enabled = !saving) {
						if (saving) {
							CircularProgressIndicator(
								modifier = Modifier.size(18.dp),
								strokeWidth = 2.dp,
							)
						} else {
							Text(stringResource(R.string.save))
						}
					}
				},
			)
		},
	) { padding ->
		Column(
			modifier = Modifier
				.fillMaxSize()
				.verticalScroll(rememberScrollState())
				.padding(padding)
				.padding(PaddingValues(16.dp)),
			verticalArrangement = Arrangement.spacedBy(12.dp),
		) {
			OutlinedTextField(
				value = name,
				onValueChange = { name = it },
				label = { Text(stringResource(R.string.album_name)) },
				singleLine = true,
				modifier = Modifier.fillMaxWidth(),
			)
			SectionTitle(stringResource(R.string.album_rule_taken))
			DateRangeRow(
				from = rules.takenFrom,
				to = rules.takenTo,
				dateFormat = dateFormat,
				onFrom = { picker = DateField.TakenFrom },
				onTo = { picker = DateField.TakenTo },
				onClear = { rules = rules.copy(takenFrom = null, takenTo = null) },
			)
			SectionTitle(stringResource(R.string.album_rule_uploaded))
			DateRangeRow(
				from = rules.uploadedFrom,
				to = rules.uploadedTo,
				dateFormat = dateFormat,
				onFrom = { picker = DateField.UploadedFrom },
				onTo = { picker = DateField.UploadedTo },
				onClear = { rules = rules.copy(uploadedFrom = null, uploadedTo = null) },
			)
			SectionTitle(stringResource(R.string.album_rule_type))
			SingleChoiceSegmentedButtonRow(modifier = Modifier.fillMaxWidth()) {
				val options = listOf(
					"all" to stringResource(R.string.album_type_all),
					"image" to stringResource(R.string.album_type_images),
					"video" to stringResource(R.string.album_type_videos),
				)
				options.forEachIndexed { index, (value, label) ->
					SegmentedButton(
						selected = rules.mediaType == value,
						onClick = { rules = rules.copy(mediaType = value) },
						shape = SegmentedButtonDefaults.itemShape(index, options.size),
					) {
						Text(label)
					}
				}
			}
			error?.let { key ->
				Text(
					text = stringResource(
						if (key == "albumNameRequired") {
							R.string.album_name_required
						} else {
							R.string.album_rules_required
						},
					),
					color = MaterialTheme.colorScheme.error,
					style = MaterialTheme.typography.bodySmall,
				)
			}
			Row(
				modifier = Modifier
					.fillMaxWidth()
					.background(MaterialTheme.colorScheme.surfaceContainerHighest, MaterialTheme.shapes.medium)
					.padding(14.dp),
				verticalAlignment = Alignment.CenterVertically,
			) {
				if (previewing) {
					CircularProgressIndicator(
						modifier = Modifier.size(18.dp),
						strokeWidth = 2.dp,
					)
				} else {
					Icon(
						imageVector = Icons.Filled.Event,
						contentDescription = null,
						tint = MaterialTheme.colorScheme.primary,
						modifier = Modifier.size(20.dp),
					)
				}
				Spacer(Modifier.width(10.dp))
				Text(
					text = if (rules.isEmpty) {
						stringResource(R.string.album_rules_required)
					} else {
						stringResource(R.string.album_preview, preview ?: 0)
					},
					style = MaterialTheme.typography.bodyMedium,
				)
			}
			Button(
				onClick = { save() },
				enabled = !saving,
				modifier = Modifier.fillMaxWidth(),
			) {
				Text(stringResource(R.string.save))
			}
		}
	}

	picker?.let { field ->
		val initial = when (field) {
			DateField.TakenFrom -> rules.takenFrom
			DateField.TakenTo -> rules.takenTo
			DateField.UploadedFrom -> rules.uploadedFrom
			DateField.UploadedTo -> rules.uploadedTo
		}
		val initialMillis = initial
			?.atStartOfDay(ZoneOffset.UTC)?.toInstant()?.toEpochMilli()
		val pickerState = rememberDatePickerState(initialSelectedDateMillis = initialMillis)
		DatePickerDialog(
			onDismissRequest = { picker = null },
			confirmButton = {
				TextButton(
					onClick = {
						val millis = pickerState.selectedDateMillis
						if (millis != null) {
							val date = Instant.ofEpochMilli(millis)
								.atZone(ZoneOffset.UTC)
								.toLocalDate()
							rules = when (field) {
								DateField.TakenFrom -> rules.copy(takenFrom = date)
								DateField.TakenTo -> rules.copy(takenTo = date)
								DateField.UploadedFrom -> rules.copy(uploadedFrom = date)
								DateField.UploadedTo -> rules.copy(uploadedTo = date)
							}
						}
						picker = null
					},
				) {
					Text(stringResource(R.string.save))
				}
			},
			dismissButton = {
				TextButton(onClick = { picker = null }) {
					Text(stringResource(R.string.cancel))
				}
			},
		) {
			DatePicker(state = pickerState)
		}
	}
}

@Composable
private fun SectionTitle(text: String) {
	Text(
		text = text,
		style = MaterialTheme.typography.titleSmall,
		modifier = Modifier.padding(top = 4.dp),
	)
}

@Composable
private fun DateRangeRow(
	from: LocalDate?,
	to: LocalDate?,
	dateFormat: DateTimeFormatter,
	onFrom: () -> Unit,
	onTo: () -> Unit,
	onClear: () -> Unit,
) {
	Row(
		modifier = Modifier.fillMaxWidth(),
		verticalAlignment = Alignment.CenterVertically,
		horizontalArrangement = Arrangement.spacedBy(8.dp),
	) {
		OutlinedButton(onClick = onFrom, modifier = Modifier.weight(1f)) {
			Text(from?.format(dateFormat) ?: stringResource(R.string.album_rule_from))
		}
		OutlinedButton(onClick = onTo, modifier = Modifier.weight(1f)) {
			Text(to?.format(dateFormat) ?: stringResource(R.string.album_rule_to))
		}
		if (from != null || to != null) {
			IconButton(onClick = onClear) {
				Icon(
					imageVector = Icons.Filled.Clear,
					contentDescription = stringResource(R.string.album_rule_clear),
				)
			}
		}
	}
}
