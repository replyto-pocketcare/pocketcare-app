package com.sanvya.app.ui.creditcards

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.sanvya.app.data.repository.CreditCardRepository
import com.sanvya.app.data.repository.LedgerRepository
import com.sanvya.app.ui.CreditCardUiModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.launch
import java.text.NumberFormat
import java.util.Locale

import androidx.compose.ui.graphics.Color


class CreditCardsViewModel(
    private val creditCardRepository: CreditCardRepository,
    private val ledgerRepository: LedgerRepository
) : ViewModel() {

    private val numberFormat = NumberFormat.getCurrencyInstance(Locale("en", "IN")).apply {
        currency = java.util.Currency.getInstance("INR")
        maximumFractionDigits = 2
    }

    private val _cards = MutableStateFlow<List<CreditCardUiModel>>(emptyList())
    val cards: StateFlow<List<CreditCardUiModel>> = _cards

    init {
        viewModelScope.launch {
            try {
                ledgerRepository.watchAccountBalances(includeArchived = false).collectLatest { balances ->
                    val cardsData = balances.filter { it.account.type.equals("creditCard", ignoreCase = true) || it.account.type.equals("credit_card", ignoreCase = true) }.mapIndexed { index, accountWithBalance ->
                        val details = creditCardRepository.getDetails(accountWithBalance.account.id)
                        val outstandingAmt = accountWithBalance.balance.amount / 100.0
                        val limitAmt = (details?.creditLimit ?: 0) / 100.0
                        
                        val avail = limitAmt - Math.abs(outstandingAmt)
                        
                        val colors = if (index % 2 == 0) {
                            listOf(Color(0xFF2C3E50), Color(0xFF1A252F))
                        } else {
                            listOf(Color(0xFFE07A5F), Color(0xFF7A3E29))
                        }
                        
                        CreditCardUiModel(
                            id = accountWithBalance.account.id,
                            cardName = accountWithBalance.account.name,
                            bankNetwork = "Bank • Visa", 
                            last4 = details?.cardLast4 ?: "****",
                            outstandingFormatted = numberFormat.format(Math.abs(outstandingAmt)),
                            availableLimitFormatted = numberFormat.format(Math.max(0.0, avail)),
                            dueDate = "Day ${details?.dueDay ?: "--"}",
                            gradientColors = colors
                        )
                    }
                    _cards.value = cardsData
                }
            } catch (e: Exception) {
                e.printStackTrace()
            }
        }
    }
}
