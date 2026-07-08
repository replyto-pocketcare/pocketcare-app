import { useQuery } from "@powersync/react";

export function usePremiumStatus() {
  const { data } = useQuery("SELECT * FROM entitlements LIMIT 1");
  const ent = data?.[0];

  if (!ent) return { isPremiumUser: false, hasActiveTrial: false, daysRemaining: 0 };

  const isPremiumUser = ent.tier === "premium";
  let hasActiveTrial = false;
  let daysRemaining = 0;

  if (ent.premium_trial_start_date) {
    const start = new Date(ent.premium_trial_start_date);
    const now = new Date();
    const diffTime = Math.abs(now.getTime() - start.getTime());
    const diffDays = Math.ceil(diffTime / (1000 * 60 * 60 * 24));
    
    if (diffDays <= 14) {
      hasActiveTrial = true;
      daysRemaining = 14 - diffDays;
    }
  }

  return { isPremiumUser, hasActiveTrial, daysRemaining };
}
