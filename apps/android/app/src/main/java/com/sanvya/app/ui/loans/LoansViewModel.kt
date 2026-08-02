package com.sanvya.app.ui.loans

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.sanvya.app.data.repository.LoansRepository
import com.sanvya.app.ui.LoanUiModel
import com.sanvya.app.data.auth.AuthRepository
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.launch
import java.text.NumberFormat
import java.util.Locale

class LoansViewModel(
    private val loansRepository: LoansRepository,
    private val authRepository: AuthRepository
) : ViewModel() {

    private val numberFormat = NumberFormat.getCurrencyInstance(Locale("en", "IN")).apply {
        currency = java.util.Currency.getInstance("INR")
        maximumFractionDigits = 0
    }

    private val _loans = MutableStateFlow<List<LoanUiModel>>(emptyList())
    val loans: StateFlow<List<LoanUiModel>> = _loans

    init {
        viewModelScope.launch {
            val userId = authRepository.currentUserId.value ?: return@launch
            try {
                loansRepository.watchLoans(userId).collectLatest { dbLoans ->
                    val uiLoans = dbLoans.map { loan ->
                        val total = loan.principal / 100.0
                        val emi = loan.emiAmount / 100.0
                        
                        val remainingEmis = Math.max(0L, loan.tenureMonths - loan.emisPaid).toInt()
                        
                        LoanUiModel(
                            id = loan.id,
                            name = loan.lender,
                            totalAmount = numberFormat.format(total),
                            emiAmount = numberFormat.format(emi),
                            remainingEmis = remainingEmis,
                            totalEmis = loan.tenureMonths.toInt(),
                            status = if (remainingEmis > 0) "Active" else "Closed",
                            nextDueDate = "Day ${loan.emiDueDay}" // Placeholder date based on due day
                        )
                    }
                    _loans.value = uiLoans
                }
            } catch (e: Exception) {
                e.printStackTrace()
            }
        }
    }
}
