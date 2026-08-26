package com.sanvya.app.ui.taxonomy

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.sanvya.app.data.auth.AuthRepository
import com.sanvya.app.data.repository.LabelRow
import com.sanvya.app.data.repository.LedgerRepository
import com.sanvya.app.domain.taxonomy.CategoryTreeNode
import com.sanvya.app.domain.taxonomy.TaxonomyCategory
import com.sanvya.app.domain.taxonomy.categoryTree
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import org.koin.core.component.KoinComponent
import org.koin.core.component.inject

data class CategoriesState(
    val nodes: List<CategoryTreeNode> = emptyList(),
    /**
     * The add row's parent options: top-level categories of the kind being
     * added. Web recomputes this from the selected kind, so switching kind
     * changes the list -- and can leave a parent selected that belongs to the
     * other kind, which is why the screen clears it.
     */
    val parentOptions: List<TaxonomyCategory> = emptyList(),
)

/**
 * Manage categories -- ported from apps/web/app/settings/categories/page.tsx.
 *
 * The tree itself is `domain.taxonomy.categoryTree`, vector-tested. What is
 * here is the live query, the draft state for the add row, and the three writes.
 *
 * **Not ported: the Auto-categorize card.** It drives
 * `apps/web/src/categorize/` -- a 905-line on-device merchant-matching engine
 * with its own seed taxonomy, normaliser and semantic matcher. That is its own
 * port, not a corner of this screen, and it is the same engine
 * `transactions/new` defers. Tracked in PARITY_AUDIT.
 *
 * Mirrors apps/ios/App/ViewModels/TaxonomyViewModels.swift.
 */
class CategoriesViewModel : ViewModel(), KoinComponent {
    private val ledgerRepository: LedgerRepository by inject()
    private val authRepository: AuthRepository by inject()

    private val _search = MutableStateFlow("")
    val search: StateFlow<String> = _search.asStateFlow()

    private val _expanded = MutableStateFlow<Set<String>>(emptySet())

    private val _newName = MutableStateFlow("")
    val newName: StateFlow<String> = _newName.asStateFlow()

    private val _newKind = MutableStateFlow("expense")
    val newKind: StateFlow<String> = _newKind.asStateFlow()

    private val _newParentId = MutableStateFlow("")
    val newParentId: StateFlow<String> = _newParentId.asStateFlow()

    fun setSearch(v: String) { _search.value = v }
    fun setNewName(v: String) { _newName.value = v }
    fun setNewParentId(v: String) { _newParentId.value = v }

    fun setNewKind(v: String) {
        _newKind.value = v
        // A parent of the OTHER kind is no longer offered, so a stale selection
        // would silently file the new category under an invisible parent.
        _newParentId.value = ""
    }

    fun toggle(id: String) {
        _expanded.value = _expanded.value.let { if (id in it) it - id else it + id }
    }

    private val all: StateFlow<List<TaxonomyCategory>> = ledgerRepository.watchCategories()
        .map { rows ->
            // Sorted here rather than in the repository: every other reader of
            // watchCategories() wants name order, and this screen is the only
            // one that groups by kind first, which is what web's
            // `ORDER BY kind, name` does.
            rows.map { TaxonomyCategory(it.id, it.name, it.kind, it.parentId) }
                .sortedWith(compareBy({ it.kind }, { it.name }))
        }
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), emptyList())

    val state: StateFlow<CategoriesState> = combine(
        all, _search, _expanded, _newKind,
    ) { categories, search, expanded, kind ->
        CategoriesState(
            nodes = categoryTree(categories, search, expanded),
            parentOptions = categories.filter { it.parentId == null && it.kind == kind },
        )
    }.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), CategoriesState())

    fun add() {
        val name = _newName.value.trim()
        if (name.isEmpty()) return
        val kind = _newKind.value
        val parentId = _newParentId.value.ifEmpty { null }
        _newName.value = ""
        _newParentId.value = ""
        viewModelScope.launch {
            val userId = authRepository.currentUserId.value ?: return@launch
            runCatching { ledgerRepository.createCategory(userId, name, kind, parentId) }
        }
    }

    fun rename(id: String, name: String) {
        val trimmed = name.trim()
        if (trimmed.isEmpty()) return
        viewModelScope.launch { runCatching { ledgerRepository.renameCategory(id, trimmed) } }
    }

    fun delete(id: String) {
        viewModelScope.launch { runCatching { ledgerRepository.deleteCategory(id) } }
    }
}

/** Manage labels -- ported from apps/web/app/settings/labels/page.tsx. */
class LabelsViewModel : ViewModel(), KoinComponent {
    private val ledgerRepository: LedgerRepository by inject()
    private val authRepository: AuthRepository by inject()

    companion object {
        /**
         * Web's default swatch for a new label and its fallback for one saved
         * without a colour. The value is web's; it is a literal there too.
         */
        const val DEFAULT_COLOR = "#b06a4f"
    }

    private val _search = MutableStateFlow("")
    val search: StateFlow<String> = _search.asStateFlow()

    private val _newName = MutableStateFlow("")
    val newName: StateFlow<String> = _newName.asStateFlow()

    private val _newColor = MutableStateFlow(DEFAULT_COLOR)
    val newColor: StateFlow<String> = _newColor.asStateFlow()

    fun setSearch(v: String) { _search.value = v }
    fun setNewName(v: String) { _newName.value = v }
    fun setNewColor(v: String) { _newColor.value = v }

    val labels: StateFlow<List<LabelRow>> = combine(
        ledgerRepository.watchLabels(), _search,
    ) { rows, search ->
        // Web tests `!search`, so only the empty string turns filtering off --
        // a single space really does filter. Copied, not corrected, so the two
        // platforms and the browser agree.
        if (search.isEmpty()) rows else rows.filter { it.name.lowercase().contains(search.lowercase()) }
    }.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), emptyList())

    fun add() {
        val name = _newName.value.trim()
        if (name.isEmpty()) return
        val color = _newColor.value
        _newName.value = ""
        viewModelScope.launch {
            val userId = authRepository.currentUserId.value ?: return@launch
            runCatching { ledgerRepository.createLabel(userId, name, color) }
        }
    }

    fun save(id: String, name: String, color: String) {
        val trimmed = name.trim()
        if (trimmed.isEmpty()) return
        viewModelScope.launch { runCatching { ledgerRepository.updateLabel(id, trimmed, color) } }
    }

    fun delete(id: String) {
        viewModelScope.launch { runCatching { ledgerRepository.deleteLabel(id) } }
    }
}
