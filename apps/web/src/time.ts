export function utcToLocalTime(utcTime: string | null | undefined, defaultLocal = "09:00"): string {
  if (!utcTime) return defaultLocal;
  const [h, m] = utcTime.split(":").map(Number);
  if (isNaN(h) || isNaN(m)) return defaultLocal;
  const d = new Date();
  d.setUTCHours(h, m, 0, 0);
  return d.toTimeString().slice(0, 5);
}

export function localToUtcTime(localTime: string): string {
  if (!localTime) return "00:00";
  const [h, m] = localTime.split(":").map(Number);
  if (isNaN(h) || isNaN(m)) return "00:00";
  const d = new Date();
  d.setHours(h, m, 0, 0);
  return `${String(d.getUTCHours()).padStart(2, "0")}:${String(d.getUTCMinutes()).padStart(2, "0")}`;
}
