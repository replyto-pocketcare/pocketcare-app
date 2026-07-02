-- PocketCare — optional card number on credit cards.
-- Purely cosmetic (for the card face); never mandatory. We store only the last 4
-- digits for privacy. The card holder name is the user's display name (dynamic).

alter table credit_card_details add column card_last4 text;
