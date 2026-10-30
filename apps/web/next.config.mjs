/** @type {import('next').NextConfig} */
export default {
  reactStrictMode: true,
  // Pages read the user's session in the browser and call Supabase directly (RLS and the erp_* functions
  // enforce access), so most of the app is static and keeps working offline from the service worker cache.
  output: process.env.NEXT_OUTPUT === "export" ? "export" : undefined,
};
