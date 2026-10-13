"use client";
import { useEffect, useState } from "react";

/** Current year. Prerendered with the build year, corrected in the browser so it never goes stale. */
export function Year() {
  const [year, setYear] = useState(new Date().getFullYear());
  useEffect(() => setYear(new Date().getFullYear()), []);
  return <>{year}</>;
}
